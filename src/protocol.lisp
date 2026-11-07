(in-package #:pty-protocol)

;;; ------------------------------------------------------------------
;;; Backend

(defclass pty-backend () ()
  (:documentation "Selects a pty implementation. Backends subclass it and set
*PTY-BACKEND* when they load."))

(defvar *pty-backend* nil)

(defgeneric backend-spawn-pty (backend command &key cols rows directory environment)
  (:documentation "Start COMMAND (a non-empty list of strings) on a new pty.
ENVIRONMENT is the complete environment as an alist of strings. → a PTY.
Signals PTY-SPAWN-ERROR."))

;;; ------------------------------------------------------------------
;;; PTY

(defclass pty ()
  ((backend :initarg :backend :reader pty-backend-of)
   (closed-p :initform nil :accessor %pty-closed-p))
  (:documentation "A child process attached to a pseudo-terminal. Backends
subclass it. One owner thread at a time; the protocol does not lock."))

(defparameter +signals+ '(:hup :int :term :kill)
  "Signals PTY-SIGNAL accepts. Windows terminates the child for :TERM and :KILL.")

(defun merge-environment (overrides &key (inherit t))
  "→ the child's environment as an alist: the parent's (when INHERIT), with
OVERRIDES (an alist) on top, and TERM defaulting to xterm-256color."
  (let ((env (when inherit
               (loop for entry in (%parent-environment)
                     for eq = (position #\= entry :start 1)
                     when eq collect (cons (subseq entry 0 eq) (subseq entry (1+ eq)))))))
    (dolist (pair overrides)
      (setf env (remove (car pair) env :key #'car :test #'string=))
      (push pair env))
    (unless (assoc "TERM" env :test #'string=)
      (push (cons "TERM" "xterm-256color") env))
    env))

(defun %parent-environment ()
  #+sbcl (sb-ext:posix-environ)
  #+ecl (ext:environ)
  #-(or sbcl ecl) '())

(defun signal-io-error (pty operation &optional code)
  "Signal PTY-IO-ERROR for OPERATION. Backends call this where a read or
write fails. A CONTINUE restart returns NIL, so a write can be dropped."
  (restart-case (error 'pty-io-error :pty pty :operation operation :code code)
    (continue ()
      :report "Ignore the failed operation."
      nil)))

(defun %check-command (command)
  (unless (and (consp command) (every #'stringp command) (plusp (length (first command))))
    (error 'type-error :datum command :expected-type '(cons string list))))

(defun spawn-pty (command &key (cols 80) (rows 24) directory environment
                               (inherit-environment t) (backend *pty-backend*))
  "Start COMMAND (list of strings; argv[0] is searched in PATH unless it has a
slash) on a new COLS × ROWS pty. ENVIRONMENT (alist) is merged over the
parent's environment unless INHERIT-ENVIRONMENT is NIL. A USE-VALUE
restart on PTY-SPAWN-ERROR retries with another command."
  (unless backend (error 'pty-no-backend))
  (%check-command command)
  (check-type cols (integer 1 65535))
  (check-type rows (integer 1 65535))
  (loop
    (restart-case
        (return (backend-spawn-pty backend command
                                   :cols cols :rows rows
                                   :directory (and directory (namestring directory))
                                   :environment (merge-environment
                                                 environment :inherit inherit-environment)))
      (use-value (new-command)
        :report "Start another command instead."
        :interactive (lambda ()
                       (format *query-io* "Command (list of strings): ")
                       (force-output *query-io*)
                       (list (read *query-io*)))
        (%check-command new-command)
        (setf command new-command)))))

(defgeneric pty-closed-p (pty)
  (:method ((pty pty)) (%pty-closed-p pty)))

(defgeneric pty-close (pty)
  (:documentation "Kill the child if it is still running, reap it, and free the
pty. Idempotent.")
  (:method ((pty pty)) nil)
  (:method :around ((pty pty))
    (unless (%pty-closed-p pty)
      (unwind-protect (call-next-method)
        (setf (%pty-closed-p pty) t)))
    nil))

(defmacro with-pty ((var command &rest keys) &body body)
  "Bind VAR to (SPAWN-PTY COMMAND ,@KEYS) around BODY, closing it afterwards."
  `(let ((,var (spawn-pty ,command ,@keys)))
     (unwind-protect (progn ,@body)
       (pty-close ,var))))

(defmacro define-pty-generic (name lambda-list &body options)
  "DEFGENERIC whose first argument is a PTY, plus an :AROUND method that
signals PTY-CLOSED-ERROR once it is closed."
  (let* ((rest-args (gensym "ARGS"))
         (required (loop for arg in lambda-list
                         until (member arg lambda-list-keywords) collect arg))
         (tail (when (nthcdr (length required) lambda-list) (list '&rest rest-args))))
    `(progn
       (defgeneric ,name ,lambda-list ,@options)
       (defmethod ,name :around ((,(first required) pty) ,@(rest required) ,@tail)
         (declare (ignore ,@(rest required) ,@(rest tail)))
         (when (%pty-closed-p ,(first required))
           (error 'pty-closed-error :pty ,(first required)))
         (call-next-method)))))

(define-pty-generic pty-read (pty &key timeout max)
  (:documentation "Wait up to TIMEOUT seconds (NIL = forever) for output.
→ an octet vector of at most MAX bytes (default 4096), empty on timeout,
or NIL once the child has closed its side (EOF)."))

(define-pty-generic pty-write (pty octets &key start end)
  (:documentation "Write OCTETS[START, END) to the child's input. → NIL.
Signals PTY-IO-ERROR (with a CONTINUE restart that drops the write) if the
child is gone."))

(defmethod pty-write :around ((pty pty) octets &key (start 0) end)
  ;; Replaces the closed-check :AROUND from DEFINE-PTY-GENERIC.
  (when (%pty-closed-p pty) (error 'pty-closed-error :pty pty))
  (unless (typep octets '(vector (unsigned-byte 8)))
    (error 'type-error :datum octets :expected-type '(vector (unsigned-byte 8))))
  (unless (and (integerp start) (<= 0 start (or end (length octets)) (length octets)))
    (error 'type-error :datum (list start end) :expected-type 'bounding-indices))
  (call-next-method)
  nil)

(define-pty-generic pty-resize (pty cols rows)
  (:documentation "Set the window size; the child gets SIGWINCH (Unix)."))

(defmethod pty-resize :before ((pty pty) cols rows)
  (check-type cols (integer 1 65535))
  (check-type rows (integer 1 65535)))

(define-pty-generic pty-size (pty)
  (:documentation "→ (values cols rows)."))

(define-pty-generic pty-signal (pty signal)
  (:documentation "Send SIGNAL (one of +SIGNALS+) to the child."))

(defmethod pty-signal :before ((pty pty) signal)
  (unless (member signal +signals+)
    (error 'type-error :datum signal :expected-type `(member ,@+signals+))))

(define-pty-generic pty-alive-p (pty)
  (:documentation "True while the child has not exited."))

(define-pty-generic pty-wait (pty &key timeout)
  (:documentation "Wait up to TIMEOUT seconds (NIL = forever) for the child to
exit. → (values exit-code signal), where SIGNAL is the terminating signal
keyword or number (Unix) and EXIT-CODE is NIL in that case; NIL on timeout."))

(define-pty-generic pty-pid (pty)
  (:documentation "→ the child's process id."))
