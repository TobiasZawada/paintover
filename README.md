# paintover

Augment hi-lock.el with properties and filters (concept study).


 This package is a modified reduced copy of hi-lock.el.
 It serves as concept study for the emacs.se question
 ["Folding custom regular expressions in Emacs?"](https://emacs.stackexchange.com/q/51819/2370).

## Reduction:
 1. The package only provides `paintover-regexp` which corresponds to `highlight-regexp`.
 2. Only the font-lock-mode support has been adapted. Overlays are not supported properly.

## Modification:
 `paintover-regexp` accepts in comparison to `highlight-regexp` two additional arguments:
 1. an expression for a plist `(PROP1 VAL1 PROP2 VAL2 ...)`.
    That is the plist provided for the `FACENAME` elements in `font-lock-keywords` entries as `'(face FACE PROP1 VAL1 PROP2 VAL2 ...)`.
    - Note the quote. The list is not evaluated.
    - nil is an acceptable `PROPERTIES` argument.
 2. a filter function `FILTER`, it is called as `(FILTER '(face FACE PROP1 VAL1 PROP2 VAL2 ...))`
    The filter can modify the list argument and return the modified list that is used for the `FACENAME` element.
 3. The prefix has changed from `hi-lock` to `paintover`.

## Notes:
  1. You have to add the properties that you use in the FACENAME
     list yourself to `font-lock-extra-managed-props`.
