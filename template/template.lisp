(in-package :docbrowser-template)

(declaim #.*compile-decl*)

(defclass parsed-file ()
  ((name            :type pathname
                    :reader parsed-file-pathspec
                    :initarg :name
                    :initform (error "name is a required parameter"))
   (modified-date   :type integer
                    :reader parsed-file-modified-date)
   (last-time-check :type integer
                    :accessor parsed-file-last-time-check)
   (template        :type function
                    :reader parsed-file-template
                    :initarg :template
                    :initform (error "template is unset")))
  (:documentation "Cached parse result"))

(defmethod initialize-instance :after ((obj parsed-file) &key &allow-other-keys)
  (setf (slot-value obj 'modified-date) (file-write-date (parsed-file-pathspec obj)))
  (setf (slot-value obj 'last-time-check) (get-universal-time)))

(defvar *cached-templates* (make-hash-table :test 'equal))
(defvar *cached-templates-lock* (bordeaux-threads:make-lock "cached-templates-lock"))

(defun parse-template-file (pathname &key binary (encoding :utf-8))
  (with-open-file (s pathname)
    (parse-template s :binary binary :encoding encoding)))

(defun exec-template-file (file data stream &key binary (encoding :utf-8))
  "Load and compile FILE and put it into the template cache if it was not
already in the cache. Then run the template using DATA and write the
output to STREAM."
  (bordeaux-threads:with-lock-held (*cached-templates-lock*)
    (let* ((pathname (pathname file))
           (cached (gethash pathname *cached-templates*)))
      (funcall (parsed-file-template (cond ((or (null cached)
                                                (> (file-write-date (parsed-file-pathspec cached))
                                                   (parsed-file-modified-date cached)))
                                            (setf (gethash pathname *cached-templates*)
                                                  (make-instance 'parsed-file
                                                                 :name pathname
                                                                 :template (parse-template-file pathname
                                                                                                :binary binary
                                                                                                :encoding encoding))))
                                           (t
                                            (setf (parsed-file-last-time-check cached) (get-universal-time))
                                            cached)))
               data stream))))

(defun exec-template-to-string (file data)
  (with-output-to-string (s)
    (exec-template-file file data s)))
