(defsystem "pty-protocol"
  :version "0.1.0"
  :description "CLOS pseudo-terminal protocol for cl-stack (spawn on a pty, read/write octets, resize, signal, wait)"
  :author "egao1980"
  :license "MIT"
  :depends-on ()
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "conditions")
               (:file "protocol"))
  :in-order-to ((test-op (test-op "pty-protocol/tests"))))

(defsystem "pty-protocol/tests"
  :depends-on ("pty-protocol" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "protocol-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
