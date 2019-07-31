;;; paintover.el --- Like highlight-regexp but map text  -*- lexical-binding: t; -*-

;; Copyright (C) 2019  Tobias Zawada

;; Author: Tobias Zawada <naehring@smtp.1und1.de>
;; Keywords: matching

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package is a modified reduced copy of hi-lock.el.
;; It serves as concept study for the question
;; "Folding custom regular expressions in Emacs?" at https://emacs.stackexchange.com/q/51819/2370.

;;; Reduction:
;; 1. The package only provides `paintover-regexp' which corresponds to `highlight-regexp'.
;; 2. Only the font-lock-mode support has been adapted. Overlays are not supported properly.

;;; Modification:
;; `paintover-regexp' accepts in comparison to `highlight-regexp' two additional arguments:
;; 1. an expression for a plist (PROP1 VAL1 PROP2 VAL2 ...).
;;    That is the plist provided for the FACENAME element in `font-lock-keywords' entries
;;    as '(face FACE PROP1 VAL1 PROP2 VAL2 ...) (see the doc string of `font-lock-keywords').
;;    - Note the quote. The list is not evaluated.
;;    - nil is an acceptable PROPERTIES argument.
;; 2. a filter function FILTER, it is called as (FILTER '(face FACE PROP1 VAL1 PROP2 VAL2 ...))
;;    The filter can modify the list argument and return the modified list that is used for the FACENAME element.
;; 3. The prefix has changed from `hi-lock` to `paintover`.
;;
;;; Notes:
;;  1. You have to add the properties that you use in the FACENAME
;;     list yourself to `font-lock-extra-managed-props'.

;;; Code:

(require 'font-lock)

(defgroup paintover nil
  "Interactively add and remove font-lock patterns for highlighting text."
  :link '(custom-manual "(emacs)Highlight Interactively")
  :group 'font-lock)

(defcustom paintover-file-patterns-range 10000
  "Limit of search in a buffer for paintover patterns.
When a file is visited and paintover mode is on, patterns starting
up to this limit are added to font-lock's patterns.  See documentation
of functions `paintover-mode' and `paintover-find-patterns'."
  :type 'integer
  :group 'paintover)

(defcustom paintover-highlight-range 200000
  "Size of area highlighted by paintover when font-lock not active.
Font-lock is not active in buffers that do their own highlighting,
such as the buffer created by `list-colors-display'.  In those buffers
paintover patterns will only be applied over a range of
`paintover-highlight-range' characters.  If font-lock is active then
highlighting will be applied throughout the buffer."
  :type 'integer
  :group 'paintover)

(defcustom paintover-exclude-modes
  '(rmail-mode mime/viewer-mode gnus-article-mode)
  "List of major modes in which paintover will not run.
For security reasons since font lock patterns can specify function
calls."
  :type '(repeat symbol)
  :group 'paintover)

(defcustom paintover-file-patterns-policy 'ask
  "Specify when paintover should use patterns found in file.
If `ask', prompt when patterns found in buffer; if bound to a function,
use patterns when function returns t (function is called with patterns
as first argument); if nil or `never' or anything else, don't use file
patterns."
  :type '(choice (const :tag "Do not use file patterns" never)
                 (const :tag "Ask about file patterns" ask)
                 (function :tag "Function to check file patterns"))
  :group 'paintover
  :version "22.1")

;; It can have a function value.
(put 'paintover-file-patterns-policy 'risky-local-variable t)

(defcustom paintover-auto-select-face nil
  "Non-nil means highlighting commands do not prompt for the face to use.
Instead, each paintover command will cycle through the faces in
`paintover-face-defaults'."
  :type 'boolean
  :version "24.4")

(defgroup paintover-faces nil
  "Faces for paintover."
  :group 'paintover
  :group 'faces)

(defface paintover-yellow
  '((((min-colors 88) (background dark))
     (:background "yellow1" :foreground "black"))
    (((background dark)) (:background "yellow" :foreground "black"))
    (((min-colors 88)) (:background "yellow1"))
    (t (:background "yellow")))
  "Default face for paintover mode."
  :group 'paintover-faces)

(defface paintover-pink
  '((((background dark)) (:background "pink" :foreground "black"))
    (t (:background "pink")))
  "Face for paintover mode."
  :group 'paintover-faces)

(defface paintover-green
  '((((min-colors 88) (background dark))
     (:background "light green" :foreground "black"))
    (((background dark)) (:background "green" :foreground "black"))
    (((min-colors 88)) (:background "light green"))
    (t (:background "green")))
  "Face for paintover mode."
  :group 'paintover-faces)

(defface paintover-blue
  '((((background dark)) (:background "light blue" :foreground "black"))
    (t (:background "light blue")))
  "Face for paintover mode."
  :group 'paintover-faces)

(defface paintover-black-b
  '((t (:weight bold)))
  "Face for paintover mode."
  :group 'paintover-faces)

(defface paintover-blue-b
  '((((min-colors 88)) (:weight bold :foreground "blue1"))
    (t (:weight bold :foreground "blue")))
  "Face for paintover mode."
  :group 'paintover-faces)

(defface paintover-green-b
  '((((min-colors 88)) (:weight bold :foreground "green1"))
    (t (:weight bold :foreground "green")))
  "Face for paintover mode."
  :group 'paintover-faces)

(defface paintover-red-b
  '((((min-colors 88)) (:weight bold :foreground "red1"))
    (t (:weight bold :foreground "red")))
  "Face for paintover mode."
  :group 'paintover-faces)

(defface paintover-black-hb
  '((t (:weight bold :height 1.67 :inherit variable-pitch)))
  "Face for paintover mode."
  :group 'paintover-faces)

(defvar-local paintover-file-patterns nil
  "Patterns found in file for paintover.  Should not be changed.")
(put 'paintover-file-patterns 'permanent-local t)

(defvar-local paintover-interactive-patterns nil
  "Patterns provided to paintover by user.  Should not be changed.")
(put 'paintover-interactive-patterns 'permanent-local t)

(defvar paintover-face-defaults
  '("paintover-yellow" "paintover-pink" "paintover-green" "paintover-blue" "paintover-black-b"
    "paintover-blue-b" "paintover-red-b" "paintover-green-b" "paintover-black-hb")
  "Default faces for paintover interactive functions.")

(defvar paintover-file-patterns-prefix "paintover"
  "Search target for finding paintover patterns at top of file.")

(defvar paintover-archaic-interface-message-used nil
  "True if user alerted that `global-paintover-mode' is now the global switch.
Earlier versions of paintover used `paintover-mode' as the global switch;
the message is issued if it appears that `paintover-mode' is used assuming
that older functionality.  This variable avoids multiple reminders.")

(defvar paintover-archaic-interface-deduce nil
  "If non-nil, sometimes assume that `paintover-mode' means `global-paintover-mode'.
Assumption is made if `paintover-mode' used in the *scratch* buffer while
a library is being loaded.")

(defvar paintover-menu
  (let ((map (make-sparse-keymap "Hi Lock")))
    (define-key-after map [highlight-regexp]
      '(menu-item "Highlight Regexp..." highlight-regexp
        :help "Highlight text matching PATTERN (a regexp)."))

    (define-key-after map [highlight-phrase]
      '(menu-item "Highlight Phrase..." highlight-phrase
        :help "Highlight text matching PATTERN (a regexp processed to match phrases)."))

    (define-key-after map [highlight-lines-matching-regexp]
      '(menu-item "Highlight Lines..." highlight-lines-matching-regexp
        :help "Highlight lines containing match of PATTERN (a regexp)."))

    (define-key-after map [highlight-symbol-at-point]
      '(menu-item "Highlight Symbol at Point" highlight-symbol-at-point
        :help "Highlight symbol found near point without prompting."))

    (define-key-after map [unhighlight-regexp]
      '(menu-item "Remove Highlighting..." unhighlight-regexp
        :help "Remove previously entered highlighting pattern."
        :enable paintover-interactive-patterns))

    (define-key-after map [paintover-write-interactive-patterns]
      '(menu-item "Patterns to Buffer" paintover-write-interactive-patterns
        :help "Insert interactively added REGEXPs into buffer at point."
        :enable paintover-interactive-patterns))

    (define-key-after map [paintover-find-patterns]
      '(menu-item "Patterns from Buffer" paintover-find-patterns
        :help "Use patterns (if any) near top of buffer."))
    map)
  "Menu for paintover mode.")

(defvar paintover-map
  (let ((map (make-sparse-keymap "Hi Lock")))
    (define-key map "\C-xwi" 'paintover-find-patterns)
    (define-key map "\C-xwl" 'highlight-lines-matching-regexp)
    (define-key map "\C-xwp" 'highlight-phrase)
    (define-key map "\C-xwh" 'highlight-regexp)
    (define-key map "\C-xw." 'highlight-symbol-at-point)
    (define-key map "\C-xwr" 'unhighlight-regexp)
    (define-key map "\C-xwb" 'paintover-write-interactive-patterns)
    map)
  "Key map for paintover.")

(defvar-local paintover-point nil
  "Save position before font-lock.")

(defun paintover-save-point (&rest _args)
  "Save position in `paintover-point' before font-lock."
  (setq paintover-point (point)))

;; Visible Functions

;;;###autoload
(define-minor-mode paintover-mode
  "Toggle selective highlighting of patterns (Hi Lock mode).
With a prefix argument ARG, enable Hi Lock mode if ARG is
positive, and disable it otherwise.  If called from Lisp, enable
the mode if ARG is omitted or nil.

Hi Lock mode is automatically enabled when you invoke any of the
highlighting commands listed below, such as \\[highlight-regexp].
To enable Hi Lock mode in all buffers, use `global-paintover-mode'
or add (global-paintover-mode 1) to your init file.

In buffers where Font Lock mode is enabled, patterns are
highlighted using font lock.  In buffers where Font Lock mode is
disabled, patterns are applied using overlays; in this case, the
highlighting will not be updated as you type.

When Hi Lock mode is enabled, a \"Regexp Highlighting\" submenu
is added to the \"Edit\" menu.  The commands in the submenu,
which can be called interactively, are:

\\[highlight-regexp] REGEXP FACE
  Highlight matches of pattern REGEXP in current buffer with FACE.

\\[highlight-phrase] PHRASE FACE
  Highlight matches of phrase PHRASE in current buffer with FACE.
  (PHRASE can be any REGEXP, but spaces will be replaced by matches
  to whitespace and initial lower-case letters will become case insensitive.)

\\[highlight-lines-matching-regexp] REGEXP FACE
  Highlight lines containing matches of REGEXP in current buffer with FACE.

\\[highlight-symbol-at-point]
  Highlight the symbol found near point without prompting, using the next
  available face automatically.

\\[unhighlight-regexp] REGEXP
  Remove highlighting on matches of REGEXP in current buffer.

\\[paintover-write-interactive-patterns]
  Write active REGEXPs into buffer as comments (if possible).  They may
  be read the next time file is loaded or when the \\[paintover-find-patterns] command
  is issued.  The inserted regexps are in the form of font lock keywords.
  (See `font-lock-keywords'.)  They may be edited and re-loaded with \\[paintover-find-patterns],
  any valid `font-lock-keywords' form is acceptable.  When a file is
  loaded the patterns are read if `paintover-file-patterns-policy' is
  `ask' and the user responds y to the prompt, or if
  `paintover-file-patterns-policy' is bound to a function and that
  function returns t.

\\[paintover-find-patterns]
  Re-read patterns stored in buffer (in the format produced by \\[paintover-write-interactive-patterns]).

When paintover is started and if the mode is not excluded or patterns
rejected, the beginning of the buffer is searched for lines of the
form:
  paintover: FOO

where FOO is a list of patterns.  The patterns must start before
position \(number of characters into buffer)
`paintover-file-patterns-range'.  Patterns will be read until
paintover: end is found.  A mode is excluded if it's in the list
`paintover-exclude-modes'."
  :group 'paintover
  :lighter (:eval (if (or paintover-interactive-patterns
			  paintover-file-patterns)
		      " Hi" ""))
  :global nil
  :keymap paintover-map
  (when (and (equal (buffer-name) "*scratch*")
             load-in-progress
             (not (called-interactively-p 'interactive))
             (not paintover-archaic-interface-message-used))
    (setq paintover-archaic-interface-message-used t)
    (if paintover-archaic-interface-deduce
        (global-paintover-mode paintover-mode)
      (warn "%s"
       "Possible archaic use of (paintover-mode).
Use (global-paintover-mode 1) in .emacs to enable paintover for all buffers,
use (paintover-mode 1) for individual buffers.  For compatibility with Emacs
versions before 22 use the following in your init file:

        (if (functionp 'global-paintover-mode)
            (global-paintover-mode 1)
          (paintover-mode 1))
")))
  (if paintover-mode
      ;; Turned on.
      (progn
	(define-key-after menu-bar-edit-menu [paintover]
	  (cons "Regexp Highlighting" paintover-menu))
	(paintover-find-patterns)
        (add-hook 'font-lock-mode-hook 'paintover-font-lock-hook nil t)
        ;; Remove regexps from font-lock-keywords (bug#13891).
	(add-hook 'change-major-mode-hook (lambda () (paintover-mode -1)) nil t)
	(add-function :before (local 'font-lock-fontify-region-function) #'paintover-save-point))
    ;; Turned off.
    (when (or paintover-interactive-patterns
	      paintover-file-patterns)
      (when paintover-interactive-patterns
	(font-lock-remove-keywords nil paintover-interactive-patterns)
	(setq paintover-interactive-patterns nil))
      (when paintover-file-patterns
	(font-lock-remove-keywords nil paintover-file-patterns)
	(setq paintover-file-patterns nil))
      (remove-overlays nil nil 'paintover-overlay t)
      (font-lock-flush))
    (define-key-after menu-bar-edit-menu [paintover] nil)
    (remove-hook 'font-lock-mode-hook 'paintover-font-lock-hook t)
    (remove-function (local 'font-lock-fontify-region-function) #'paintover-save-point)))

;;;###autoload
(define-globalized-minor-mode global-paintover-mode
  paintover-mode turn-on-paintover-if-enabled
  :group 'paintover)

(defun turn-on-paintover-if-enabled ()
  (setq paintover-archaic-interface-message-used t)
  (unless (memq major-mode paintover-exclude-modes)
    (paintover-mode 1)))

(defvar paintover-read-properties-history nil
  "History for `paintover-read-properties'.")

(defun paintover-read-properties ()
  "Read text/overlay property list from minibuffer."
  (read-from-minibuffer "Property list (as Lisp expression): "
			nil
			nil
			t
			paintover-read-properties-history
			"nil"
			))

;;;###autoload
(defun paintover-regexp (regexp &optional face properties filter)
  "Set face of each match of REGEXP to FACE with PROPERTIES.
Interactively, prompt for REGEXP using `read-regexp', then FACE.
Use the global history list for FACE.

Use Font lock mode, if enabled, to highlight REGEXP.  Otherwise,
use overlays for highlighting.  If overlays are used, the
highlighting will not update as you type."
  (interactive
   (list
    (paintover-regexp-okay
     (read-regexp "Regexp to highlight" 'regexp-history-last))
    (paintover-read-face-name)
    (paintover-read-properties)
    (read-from-minibuffer "Filter (Elisp function): " nil nil t nil "'quote")))
  (or (facep face) (setq face 'hi-yellow))
  (unless paintover-mode (paintover-mode 1))
  (paintover-set-pattern regexp face properties filter))

(defun paintover-keyword->face (keyword)
  (cadr (cadr (cadr keyword))))    ; Keyword looks like (REGEXP (0 'FACE) ...).

(declare-function x-popup-menu "menu.c" (position menu))

(defvar-local paintover--unused-faces nil
  "List of faces that is not used and is available for highlighting new text.
Face names from this list come from `paintover-face-defaults'.")

;;;###autoload
(defun paintover-unface-buffer (regexp)
  "Remove highlighting of each match to REGEXP set by paintover.
Interactively, prompt for REGEXP, accepting only regexps
previously inserted by paintover interactive functions.
If REGEXP is t (or if \\[universal-argument] was specified interactively),
then remove all paintover highlighting."
  (interactive
   (cond
    (current-prefix-arg (list t))
    ((and (display-popup-menus-p)
          (listp last-nonmenu-event)
          use-dialog-box)
     (catch 'snafu
       (or
        (x-popup-menu
         t
         (cons
          `keymap
          (cons "Select Pattern to Unhighlight"
                (mapcar (lambda (pattern)
                          (list (car pattern)
                                (format
                                 "%s (%s)" (car pattern)
                                 (paintover-keyword->face pattern))
                                (cons nil nil)
                                (car pattern)))
                        paintover-interactive-patterns))))
        ;; If the user clicks outside the menu, meaning that they
        ;; change their mind, x-popup-menu returns nil, and
        ;; interactive signals a wrong number of arguments error.
        ;; To prevent that, we return an empty string, which will
        ;; effectively disable the rest of the function.
        (throw 'snafu '("")))))
    (t
     ;; Un-highlighting triggered via keyboard action.
     (unless paintover-interactive-patterns
       (error "No highlighting to remove"))
     ;; Infer the regexp to un-highlight based on cursor position.
     (let* ((defaults (mapcar #'car paintover-interactive-patterns)))
       (list
        (completing-read (if (null defaults)
                             "Regexp to unhighlight: "
                           (format "Regexp to unhighlight (default %s): "
                                   (car defaults)))
                         paintover-interactive-patterns
			 nil t nil nil defaults))))))
  (dolist (keyword (if (eq regexp t) paintover-interactive-patterns
                     (list (assoc regexp paintover-interactive-patterns))))
    (when keyword
      (let ((face (paintover-keyword->face keyword)))
        ;; Make `face' the next one to use by default.
        (when (symbolp face)          ;Don't add it if it's a list (bug#13297).
          (add-to-list 'paintover--unused-faces (face-name face))))
      ;; FIXME: Calling `font-lock-remove-keywords' causes
      ;; `font-lock-specified-p' to go from nil to non-nil (because it
      ;; calls font-lock-set-defaults).  This is yet-another bug in
      ;; font-lock-add/remove-keywords, which we circumvent here by
      ;; testing `font-lock-fontified' (bug#19796).
      (if font-lock-fontified (font-lock-remove-keywords nil (list keyword)))
      (setq paintover-interactive-patterns
            (delq keyword paintover-interactive-patterns))
      (remove-overlays
       nil nil 'paintover-overlay-regexp (paintover--hashcons (car keyword)))
      (font-lock-flush))))

;;;###autoload
(defun paintover-write-interactive-patterns ()
  "Write interactively added patterns, if any, into buffer at point.

Interactively added patterns are those normally specified using
`highlight-regexp' and `highlight-lines-matching-regexp'; they can
be found in variable `paintover-interactive-patterns'."
  (interactive)
  (if (null paintover-interactive-patterns)
      (error "There are no interactive patterns"))
  (let ((beg (point)))
    (mapc
     (lambda (pattern)
       (insert (format "%s: (%s)\n"
		       paintover-file-patterns-prefix
		       (prin1-to-string pattern))))
     paintover-interactive-patterns)
    (comment-region beg (point)))
  (when (> (point) paintover-file-patterns-range)
    (warn "Inserted keywords not close enough to top of file")))

;; Implementation Functions

(defun paintover-process-phrase (phrase)
  "Convert regexp PHRASE to a regexp that matches phrases.

Blanks in PHRASE replaced by regexp that matches arbitrary whitespace
and initial lower-case letters made case insensitive."
  (let ((mod-phrase nil))
    ;; FIXME fragile; better to just bind case-fold-search?  (Bug#7161)
    (setq mod-phrase
          (replace-regexp-in-string
           "\\(^\\|\\s-\\)\\([a-z]\\)"
           (lambda (m) (format "%s[%s%s]"
                               (match-string 1 m)
                               (upcase (match-string 2 m))
                               (match-string 2 m))) phrase))
    ;; FIXME fragile; better to use search-spaces-regexp?
    (setq mod-phrase
          (replace-regexp-in-string
           "\\s-+" "[ \t\n]+" mod-phrase nil t))))

(defun paintover-regexp-okay (regexp)
  "Return REGEXP if it appears suitable for a font-lock pattern.

Otherwise signal an error.  A pattern that matches the null string is
not suitable."
  (cond
   ((null regexp)
    (error "Regexp cannot match nil"))
   ((string-match regexp "")
    (error "Regexp cannot match an empty string"))
   (t regexp)))

(defun paintover-read-face-name ()
  "Return face for interactive highlighting.
When `paintover-auto-select-face' is non-nil, just return the next face.
Otherwise, or with a prefix argument, read a face from the minibuffer
with completion and history."
  (unless paintover-interactive-patterns
    (setq paintover--unused-faces paintover-face-defaults))
  (let* ((last-used-face
	  (when paintover-interactive-patterns
	    (face-name (paintover-keyword->face
                        (car paintover-interactive-patterns)))))
	 (defaults (append paintover--unused-faces
			   (cdr (member last-used-face paintover-face-defaults))
			   paintover-face-defaults))
	 face)
          (if (and paintover-auto-select-face (not current-prefix-arg))
	(setq face (or (pop paintover--unused-faces) (car defaults)))
      (setq face (completing-read
		  (format "Highlight using face (default %s): "
			  (car defaults))
		  obarray 'facep t nil 'face-name-history defaults))
      ;; Update list of un-used faces.
      (setq paintover--unused-faces (remove face paintover--unused-faces))
      ;; Grow the list of defaults.
      (add-to-list 'paintover-face-defaults face t))
    (intern face)))

(defun paintover-set-pattern (regexp face properties &optional filter)
  "Highlight REGEXP with FACE and PROPERTIES mapped through FILTER.
FILTER defaults to 'quote."
  ;; Hashcons the regexp, so it can be passed to remove-overlays later.
  (setq regexp (paintover--hashcons regexp))
  (let* ((face-prop-spec (append (list 'face face) properties))
	 (pattern (list regexp (list 0
				     (if filter `(funcall ,filter (quote ,face-prop-spec))
				       `(quote ,face-prop-spec))
					       'prepend)))
        (no-matches t))
    ;; Refuse to highlight a text that is already highlighted.
    (if (assoc regexp paintover-interactive-patterns)
        (add-to-list 'paintover--unused-faces (face-name face))
      (push pattern paintover-interactive-patterns)
      (if (and font-lock-mode (font-lock-specified-p major-mode))
	  (progn
	    (font-lock-add-keywords nil (list pattern) t)
	    (cl-loop for prop on properties by #'cddr do
		     (pushnew (car prop) font-lock-extra-managed-props))
	    (font-lock-flush))
        (let* ((range-min (- (point) (/ paintover-highlight-range 2)))
               (range-max (+ (point) (/ paintover-highlight-range 2)))
               (search-start
                (max (point-min)
                     (- range-min (max 0 (- range-max (point-max))))))
               (search-end
                (min (point-max)
                     (+ range-max (max 0 (- (point-min) range-min))))))
          (save-excursion
            (goto-char search-start)
            (while (re-search-forward regexp search-end t)
              (when no-matches (setq no-matches nil))
              (let ((overlay (make-overlay (match-beginning 0) (match-end 0))))
                (overlay-put overlay 'paintover-overlay t)
                (overlay-put overlay 'paintover-overlay-regexp regexp)
                (overlay-put overlay 'face face)
		(cl-loop for prop on properties by #'cddr do
			 (overlay-put overlay (car prop) (cadr prop))))
              (goto-char (match-end 0)))
            (when no-matches
              (add-to-list 'paintover--unused-faces (face-name face))
              (setq paintover-interactive-patterns
                    (cdr paintover-interactive-patterns)))))))))

(defun paintover-set-file-patterns (patterns)
  "Replace file patterns list with PATTERNS and refontify."
  (when (or paintover-file-patterns patterns)
    (font-lock-remove-keywords nil paintover-file-patterns)
    (setq paintover-file-patterns patterns)
    (font-lock-add-keywords nil paintover-file-patterns t)
    (font-lock-flush)))

(defun paintover-find-patterns ()
  "Add patterns from the current buffer to the list of paintover patterns."
  (interactive)
  (unless (memq major-mode paintover-exclude-modes)
    (let ((all-patterns nil)
          (target-regexp (concat "\\<" paintover-file-patterns-prefix ":")))
      (save-excursion
	(save-restriction
	  (widen)
	  (goto-char (point-min))
	  (re-search-forward target-regexp
			     (+ (point) paintover-file-patterns-range) t)
	  (beginning-of-line)
	  (while (and (re-search-forward target-regexp (+ (point) 100) t)
		      (not (looking-at "\\s-*end")))
            (condition-case nil
                (setq all-patterns (append (read (current-buffer)) all-patterns))
              (error (message "Invalid pattern list expression at %d"
                              (line-number-at-pos)))))))
      (when (and all-patterns
                 paintover-mode
                 (cond
                  ((eq this-command 'paintover-find-patterns) t)
                  ((functionp paintover-file-patterns-policy)
                   (funcall paintover-file-patterns-policy all-patterns))
                  ((eq paintover-file-patterns-policy 'ask)
                   (y-or-n-p "Add patterns from this buffer to paintover? "))
                  (t nil)))
        (paintover-set-file-patterns all-patterns)
        (if (called-interactively-p 'interactive)
            (message "paintover added %d patterns." (length all-patterns)))))))

(defun paintover-font-lock-hook ()
  "Add paintover patterns to font-lock's."
  (when font-lock-fontified
    (font-lock-add-keywords nil paintover-file-patterns t)
    (font-lock-add-keywords nil paintover-interactive-patterns t)))

(defvar paintover--hashcons-hash
  (make-hash-table :test 'equal :weakness t)
  "Hash table used to hash cons regexps.")

(defun paintover--hashcons (string)
  "Return unique object equal to STRING."
  (or (gethash string paintover--hashcons-hash)
      (puthash string string paintover--hashcons-hash)))

(defun paintover-unload-function ()
  "Unload the Paintover library."
  (global-paintover-mode -1)
  ;; continue standard unloading
  nil)

(defun paintover-in (pos begin end)
  "Test whether POS is within the interval from BEGIN to END."
  (and (<= begin pos)
       (<= pos end)))

(provide 'paintover)
;;; paintover.el ends here
