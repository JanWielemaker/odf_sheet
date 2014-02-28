# ODF-sheet: a SWI-Prolog library for analyzing ODF spreadsheets

ODF-sheet is a SWI-Prolog library  for   analysing  ODF spreadsheets. It
covers representing the spreadsheet as a Prolog fact base which includes
cell contents, cell types,  cell  formulas   and  cell  style (spanning,
colour, font, etc). On top of  that,   it  provides facilities to reason
about formula dependencies and discover  regions with similar properties
(e.g., a region of cells with labels).

## Processing MicroSoft Excel files

This library only processes ODF (Open Document Format) files. ODS is the
ODF sub-format for spreadsheets. Open Office  and Libre Office ship with
a tool called =unoconv= to do batch  conversion of MicroSoft excel files
using the following command:

  ==
  % unoconv -f ods *.xlsx
  ==

## Acknowledgements

This library was developed in the context  of COMMIT/, and in particular
the Data2Semantics project thereof.

[commit.png;height="80pt"](http://www.commit-nl.nl/)
[data2semantics.png;height="80pt",align="right"](http://www.data2semantics.org/)















