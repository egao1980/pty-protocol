(in-package #:pty-protocol)

(define-condition pty-error (error)
  ((pty :initarg :pty :initform nil :reader pty-error-pty))
  (:report (lambda (c s) (format s "PTY error~@[ on ~A~]" (pty-error-pty c)))))

(define-condition pty-no-backend (pty-error) ()
  (:report (lambda (c s)
             (declare (ignore c))
             (format s "*PTY-BACKEND* is NIL. Load pty-backend-native."))))

(define-condition pty-spawn-error (pty-error)
  ((command :initarg :command :reader pty-spawn-error-command)
   (code :initarg :code :initform nil :reader pty-spawn-error-code
         :documentation "errno (Unix) or GetLastError (Windows), if known.")
   (message :initarg :message :initform nil :reader pty-spawn-error-message))
  (:report (lambda (c s)
             (format s "Could not start ~S on a pty~@[: ~A~]~@[ (code ~A)~]"
                     (pty-spawn-error-command c) (pty-spawn-error-message c)
                     (pty-spawn-error-code c)))))

(define-condition pty-closed-error (pty-error) ()
  (:report (lambda (c s) (format s "PTY ~A is closed" (pty-error-pty c)))))

(define-condition pty-io-error (pty-error)
  ((operation :initarg :operation :reader pty-io-error-operation)
   (code :initarg :code :initform nil :reader pty-io-error-code))
  (:report (lambda (c s)
             (format s "PTY ~(~A~) failed~@[ (code ~A)~]~@[ on ~A~]"
                     (pty-io-error-operation c) (pty-io-error-code c) (pty-error-pty c)))))

(define-condition pty-native-unavailable (pty-error)
  ((reason :initarg :reason :reader pty-native-unavailable-reason))
  (:report (lambda (c s)
             (format s "Native pty library unavailable: ~A" (pty-native-unavailable-reason c)))))
