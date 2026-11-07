(defpackage #:pty-protocol
  (:use #:cl)
  (:nicknames #:stack-pty)
  (:export
   ;; conditions
   #:pty-error #:pty-error-pty
   #:pty-spawn-error #:pty-spawn-error-command #:pty-spawn-error-code
   #:pty-spawn-error-message
   #:pty-closed-error
   #:pty-io-error #:pty-io-error-operation #:pty-io-error-code
   #:pty-native-unavailable #:pty-native-unavailable-reason
   #:pty-no-backend
   ;; backend
   #:pty-backend #:*pty-backend* #:backend-spawn-pty
   ;; pty
   #:pty #:pty-backend-of
   #:spawn-pty #:with-pty
   #:pty-read #:pty-write #:pty-resize #:pty-size #:pty-signal
   #:pty-alive-p #:pty-wait #:pty-pid #:pty-close #:pty-closed-p
   #:+signals+
   #:merge-environment
   #:signal-io-error))
