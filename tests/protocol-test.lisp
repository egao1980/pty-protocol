(in-package #:pty-protocol/tests)

;;; A mock backend: the "child" echoes what it is written, upper-cased.

(defclass mock-backend (pp:pty-backend) ())

(defclass mock-pty (pp:pty)
  ((command :initarg :command :reader mock-command)
   (env :initarg :env :reader mock-env)
   (size :initarg :size :accessor mock-size)
   (buffer :initform '() :accessor mock-buffer)
   (exited :initform nil :accessor mock-exited)
   (closes :initform 0 :accessor mock-closes)))

(defmethod pp:backend-spawn-pty ((b mock-backend) command &key cols rows directory environment)
  (declare (ignore directory))
  (when (string= (first command) "missing")
    (error 'pp:pty-spawn-error :command command :code 2 :message "not found"))
  (make-instance 'mock-pty :backend b :command command :env environment
                           :size (list cols rows)))

(defmethod pp:pty-write ((p mock-pty) octets &key (start 0) end)
  (when (mock-exited p) (pp:signal-io-error p :write 32))
  (loop for i from start below (or end (length octets))
        do (setf (mock-buffer p)
                 (append (mock-buffer p) (list (char-code (char-upcase (code-char (aref octets i))))))))
  nil)

(defmethod pp:pty-read ((p mock-pty) &key timeout (max 4096))
  (declare (ignore timeout))
  (cond ((mock-buffer p)
         (let ((n (min max (length (mock-buffer p)))))
           (prog1 (coerce (subseq (mock-buffer p) 0 n) '(vector (unsigned-byte 8)))
             (setf (mock-buffer p) (nthcdr n (mock-buffer p))))))
        ((mock-exited p) nil)
        (t (make-array 0 :element-type '(unsigned-byte 8)))))

(defmethod pp:pty-resize ((p mock-pty) cols rows) (setf (mock-size p) (list cols rows)))
(defmethod pp:pty-size ((p mock-pty)) (values-list (mock-size p)))
(defmethod pp:pty-signal ((p mock-pty) signal) (setf (mock-exited p) signal))
(defmethod pp:pty-alive-p ((p mock-pty)) (not (mock-exited p)))
(defmethod pp:pty-wait ((p mock-pty) &key timeout)
  (declare (ignore timeout))
  (if (mock-exited p) (values nil (mock-exited p)) nil))
(defmethod pp:pty-pid ((p mock-pty)) 42)
(defmethod pp:pty-close ((p mock-pty)) (incf (mock-closes p)))

(defun octets (s) (map '(vector (unsigned-byte 8)) #'char-code s))

(defmacro with-mock ((var command &rest keys) &body body)
  `(let ((pp:*pty-backend* (make-instance 'mock-backend)))
     (pp:with-pty (,var ,command ,@keys) ,@body)))

(deftest no-backend
  (let ((pp:*pty-backend* nil))
    (ok (signals (pp:spawn-pty '("sh")) 'pp:pty-no-backend))))

(deftest spawn-defaults-and-validation
  (with-mock (p '("sh" "-c" "x"))
    (ok (equal (multiple-value-list (pp:pty-size p)) '(80 24)))
    (ok (equal (mock-command p) '("sh" "-c" "x"))))
  (let ((pp:*pty-backend* (make-instance 'mock-backend)))
    (ok (signals (pp:spawn-pty '()) 'type-error))
    (ok (signals (pp:spawn-pty "sh") 'type-error))
    (ok (signals (pp:spawn-pty '("sh") :cols 0) 'type-error))))

(deftest environment-merging
  (let ((env (pp:merge-environment '(("FOO" . "1")) :inherit nil)))
    (ok (equal (cdr (assoc "FOO" env :test #'string=)) "1"))
    (ok (equal (cdr (assoc "TERM" env :test #'string=)) "xterm-256color")))
  (let ((env (pp:merge-environment '(("TERM" . "dumb")) :inherit nil)))
    (ok (equal (cdr (assoc "TERM" env :test #'string=)) "dumb"))
    (ok (= 1 (count "TERM" env :key #'car :test #'string=))))
  (ok (assoc "PATH" (pp:merge-environment '()) :test #'string=)))

(deftest environment-is-opaque-in-backtraces
  (with-mock (p '("sh") :environment '(("SECRET" . "hunter2")))
    (ok (typep (mock-env p) 'pp:pty-environment))
    (ng (search "hunter2" (prin1-to-string (mock-env p))))
    (ok (equal (cdr (assoc "SECRET" (pp:pty-environment-entries (mock-env p))
                           :test #'string=))
               "hunter2"))))

(deftest spawn-error-use-value
  (let ((pp:*pty-backend* (make-instance 'mock-backend)))
    (ok (signals (pp:spawn-pty '("missing")) 'pp:pty-spawn-error))
    (let ((p (handler-bind ((pp:pty-spawn-error (lambda (c) (use-value '("sh") c))))
               (pp:spawn-pty '("missing")))))
      (ok (equal (mock-command p) '("sh")))
      (pp:pty-close p))))

(deftest read-write-resize
  (with-mock (p '("sh"))
    (pp:pty-write p (octets "abc") :start 1)
    (ok (equalp (pp:pty-read p :max 1) (octets "B")))
    (ok (equalp (pp:pty-read p) (octets "C")))
    (ok (zerop (length (pp:pty-read p :timeout 0))))
    (pp:pty-resize p 100 30)
    (ok (equal (multiple-value-list (pp:pty-size p)) '(100 30)))
    (ok (signals (pp:pty-resize p 0 30) 'type-error))
    (ok (signals (pp:pty-write p "str") 'type-error))))

(deftest signal-wait-eof
  (with-mock (p '("sh"))
    (ok (pp:pty-alive-p p))
    (ng (pp:pty-wait p :timeout 0))
    (ok (signals (pp:pty-signal p :usr1) 'type-error))
    (pp:pty-signal p :term)
    (ng (pp:pty-alive-p p))
    (ok (equal (multiple-value-list (pp:pty-wait p)) '(nil :term)))
    (ok (null (pp:pty-read p)))))

(deftest write-after-exit-continue
  (with-mock (p '("sh"))
    (pp:pty-signal p :kill)
    (ok (signals (pp:pty-write p (octets "x")) 'pp:pty-io-error))
    (ok (null (handler-bind ((pp:pty-io-error #'continue))
                (pp:pty-write p (octets "x")))))))

(deftest close-is-idempotent-and-guards
  (let* ((pp:*pty-backend* (make-instance 'mock-backend))
         (p (pp:spawn-pty '("sh"))))
    (pp:pty-close p)
    (pp:pty-close p)
    (ok (= 1 (mock-closes p)))
    (ok (pp:pty-closed-p p))
    (ok (signals (pp:pty-read p) 'pp:pty-closed-error))
    (ok (signals (pp:pty-write p (octets "x")) 'pp:pty-closed-error))
    (ok (signals (pp:pty-pid p) 'pp:pty-closed-error))))
