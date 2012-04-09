(in-package :template)

(declaim #.*compile-decl*)

(defvar *begin-code* "<%")
(defvar *end-code* "%>")

(defun make-stream-template-lexer (input-stream)
  (let ((lexer-actions `(("^[ \\n]+" ,(constantly :blank))
                         ("^if" ,(constantly (list 'if nil)))
                         ("^endif" ,(constantly (list 'endif nil)))
                         ("^while" ,(constantly (list 'while nil)))
                         ("^endwhile" ,(constantly (list 'endwhile nil)))
                         ("^," ,(constantly (list '|,| nil)))
                         ("^([a-zA-Z_][a-zA-Z_0-9]*)" ,#'(lambda (exprs) (list 'symbol (aref exprs 0))))
                         ("^\"([^\"]*)\"" ,#'(lambda (exprs) (list 'string (aref exprs 0))))))
        (state :template)
        (current-line nil)
        (current-position 0)
        (input-finish nil))

    #'(lambda ()
        (labels ((read-template ()
                   (let ((pos (search *begin-code* current-line :start2 current-position)))
                     (if (null pos)
                         ;; no start code on this line, return the entire line
                         (let ((result (subseq current-line current-position)))
                           (setq current-position (length current-line))
                           (list 'template result))
                         ;; start code found, return the prefix and switch state
                         (let ((result (subseq current-line current-position pos)))
                           (setq current-position (+ pos (length *begin-code*)))
                           (setq state :code)
                           (list 'template result)))))

                 (read-code ()
                   (if (and (>= (length current-line)
                                (+ current-position (length *end-code*)))
                            (string= (subseq current-line current-position (+ current-position (length *end-code*)))
                                     *end-code*))
                       ;; End code was found
                       (progn
                         (incf current-position (length *end-code*))
                         (setq state :template)
                         :blank)
                       ;; No end code found, check the actions
                       (loop
                          with longest-match-length = 0
                          with longest-match-exprs = nil
                          with longest-match-action = nil
                          for (regex action) in lexer-actions                      
                          do (multiple-value-bind (result exprs)
                                 (cl-ppcre:scan-to-strings regex current-line :start current-position)
                               (when (and result
                                          (> (length result) longest-match-length))
                                 (setq longest-match-length (length result))
                                 (setq longest-match-exprs exprs)
                                 (setq longest-match-action action)))
                          finally (if (plusp longest-match-length)
                                      (progn
                                        (incf current-position longest-match-length)
                                        (return (funcall longest-match-action longest-match-exprs)))
                                      (error "unmached string: ~s" (subseq current-line current-position))))))

                 (read-next-line ()
                   (unless input-finish
                     (setq current-line (read-line input-stream nil nil))
                     (setq current-position 0)
                     (if current-line
                         :blank
                         (progn
                           (setq input-finish t)
                           nil))))

                 (parse-token ()
                   (cond ((null current-line)
                          (read-next-line))
                         ((>= current-position (length current-line))
                          (if (eq state :template)
                              ;; If processing the template part, return a newline
                              (progn
                                (read-next-line)
                                (list 'template (string #\Newline)))
                              ;; Else, simply process the next line
                              (read-next-line)))
                         (t
                          (ecase state
                            (:template (read-template))
                            (:code (read-code)))))))

          (loop
             for token = (parse-token)
             if (null token) return nil
             unless (eq token :blank)
             return (apply #'values token))))))

(defun debug-lexer (string)
  (with-input-from-string (s string)
    (let ((lex (make-stream-template-lexer s)))
      (loop
         for (a b) = (multiple-value-list (funcall lex))
         while a
         do (format t "~s ~s~%" a b)))))

(yacc:define-parser *template-parser*
  (:start-symbol document)
  (:terminals (template symbol string if endif while endwhile |,|))

  (document
   (document-nodes #'(lambda (doc) `(progn ,@doc))))

  (document-nodes
   (document-node document-nodes #'(lambda (n rest) (append (list n) rest)))
   nil)

  (document-node
   (template #'(lambda (v) `(print ,v)))
   (if expression document-nodes endif #'(lambda (v1 expr document v4)
                                           (declare (ignore v1 v4))
                                           `(if ,expr (progn ,@document))))

   (while expression document-nodes endwhile #'(lambda (v1 expr document v4)
                                                 (declare (ignore v1 v4))
                                                 `(loop while ,expr do (progn ,@document)))))

  (expression
   (symbol #'(lambda (v) `(gethash ,v *current-arguments-context*))))
  )
