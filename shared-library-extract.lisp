(in-package :cl-user)

(in-package :shared-library-extract)

(defvar *object-tool* "otool")
(defvar *cp* "cp")
(defvar *copyable-library-paths* (list "/opt/local/lib"))
(defvar *install-name-tool* "install_name_tool")

(defun object-tool (path)
  (flet ((process-line (line) (first (str:split " " (str:trim line)))))
    (with-input-from-string (output (uiop:run-program (list *object-tool* "-L" path)
                                                      :output '(:string :stripped t)))
      (loop for line = (read-line output nil)
            while (not (null line))
            collect (process-line line)))))

(defun copy-library-p (library-path)
  (find-if (lambda (i) (str:containsp i library-path)) *copyable-library-paths*))

(defun copy-file (from to)
  (format t "Copy file ~a to ~a~%" from to)
  (uiop:run-program (list *cp* from to)))

(defun file-name (path)
  (car (last (str:split "/" path))))

(defun file-folder (full-file-path)
  "Return the containing folder path for a file"
  (subseq full-file-path 0
          (- (length full-file-path) 1
             (position #\/ (reverse full-file-path)))))

(defun install-name (from to path)
  (uiop:run-program (list *install-name-tool* "-change"
                          from to path)))

(defun install-id (id path)
  (uiop:run-program (list *install-name-tool* "-id"
                          id path)))

(defun install-names (library)
  (format t "Install names for library ~a~%" library)
  (install-id (format nil "@loader_path/~a" (file-name library)) library)
  (loop for object in (object-tool library)
        if (copy-library-p object)
          do (install-name object (format nil "@loader_path/~a" (file-name object)) library)))

(defun library-dependency-tree (library-path)
  (let ((queue (object-tool library-path))
        (seen-libraries))
    (remove-duplicates
     (loop for library = (pop queue)
           while (not (null library))
           if (copy-library-p library)
             do (unless (find library seen-libraries :test #'equal)
                  (push library seen-libraries)
                  (setf queue (append queue (rest (object-tool library))))
                  (format t "Process Library: ~a ~%Depends on:~a~%" library (rest (object-tool library))))
           if (copy-library-p library)
             collect library)
     :test #'equal)))

(defun process-library (library-path &optional destination)
  (let ((destination (if destination destination (file-folder library-path))))
    (loop for library in (library-dependency-tree library-path)
          do (let ((destination-path (format nil "~a/~a" destination (file-name library))))
               (copy-file library destination-path)
               (install-names destination-path)))))

(defun process-libraries (libraries destination)
  (mapcar (lambda (i) (process-library i destination)) libraries))