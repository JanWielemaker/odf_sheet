# ODF-sheet: a SWI-Prolog library for analyzing ODF spreadsheets

ODF-sheet is a SWI-Prolog library for   extracting  information from ODF
spreadsheets. It covers representing the spreadsheet   as  a Prolog fact
base which includes cell contents, cell   types,  cell formulas and cell
style (spanning, colour,  font,  etc).  On   top  of  that,  it provides
facilities to reason about  formula   dependencies  and discover regions
with similar properties (e.g., a region of cells with labels).

## Processing MicroSoft Excel files

This library only processes ODF (Open Document Format) files. ODS is the
ODF sub-format for spreadsheets. Open Office  and Libre Office ship with
a tool called =unoconv= to do batch  conversion of MicroSoft excel files
using the following command:

  ==
  % unoconv -f ods *.xlsx
  ==

## Library overview

The library creates a subdirectory =ods=.   The  main library components
are described in the sections below.

### library(ods/table)

This library provides the main functionality. The content of an ODS file
is compiled into a set of Prolog facts   in the calling module using the
ods_load/1:

  ==
  ?- ods_load('mydata.ods').
  ==

After this call, the data can  be   queried  using the predicates below,
where `X` and `Y` are  the  column   number  and  row  number. Cells are
addressed with integers. The conventional column   names, e.g., =AB=, is
translated into column numbers using   column_name/2. For convience, the
predicates below accept a column name for the `X` argument.

  - cell_value(:Sheet, ?X, ?Y, ?Value)
  - cell_type(:Sheet, ?X, ?Y, ?Type)
  - cell_formula(:Sheet, ?X, ?Y, ?Type)
  - cell_style(:Sheet, ?X, ?Y, ?Property)

### library(ods/datasource)

This library deals with rectangular  areas   in  sheets.  Such areas are
represented as a term with the shape  below.   Sheet  is the name of the
sheet,  `SX`,`SY`  denotes  the  top-left    corner  and  `EX`,`EY`  the
bottom-right corner. Ranges are _inclusive_,  i.e.,   a  cell range with
`SX` == `EX` and `SY` == `EY` denotes a single cell.

  ==
  cell_range(Sheet, SX,SY, EX,EY)
  ==

Data sources are typically generated  by library(ods/recognise), notably
sheet_bb/2 returns the bounding box of all non-empty cells. For example,
the data in a sheet can be returned row-by-row on backtracking using the
following sequence, where Row is a list of values.

  ==
  ?- bb_sheet(Sheet, BB),
	      ds_row_slice(BB, Y, Row),
	      ds_matrix(BB, cell_value, [Row]).
  ==


### library(ods/recognise)

This library is used to find blocks in a sheet.  The main predicates are

  - sheet_bb(:Sheet, -DataSource)
  Finds the bounding box of all non-empty cells in the sheet.
  - cell_class(:Sheet, ?SX, ?SY, ?Class)
  Classify a cell.  This is similar to cell_type/4, but in addition
  the the formal types, the extra types =empty= is supported for a
  cell that does not appear in the data or has an empty string as
  value and the class style(Style) is used for cells that have
  an associated style.
  - anchor(:DataSource, ?Type)

## Status

  - Basic access to the library should be  considered stable.

  - Parsing of ODS formulas (using [Open
    Formula](http://en.wikipedia.org/wiki/OpenFormula)) is complete, but
    evaluation of these formulas is not.

  - There is some support for indentifying larger units on sheets, such
    as a table with headers.  This support is very incomplete and not
    well tested.


## Acknowledgements

This library was developed in the context  of COMMIT/, and in particular
the Data2Semantics project thereof.

[commit.png;height="80pt"](http://www.commit-nl.nl/)
[data2semantics.png;height="80pt",align="right"](http://www.data2semantics.org/)

@see library(csv) can be used to access comma separated files. The added
value of this library  is  access   to  formulas,  fonts,  colours, cell
spanning, etc. for supporting tools to  analyse the logical structure of
spreadsheets.













