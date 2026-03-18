# Readme for the package semesterplannerLua

Author: Lukas Heindl (`oss.heindl+latex@protonmail.com`).

<!-- CTAN page: [timberborndrawing](https://ctan.org/pkg/timberborndrawing) -->

![A teaser how the output of this package looks like](assets/teaser.png)

## License
The LaTeX package `semesterplannerLua` is distributed under the LPPL 1.3 license.

## Description

TODO

## Installation

For a manual installation:

* put the files `timberborndrawing.ins` and `timberborndrawing.dtx` in the
same directory;
* run `latex timberborndrawing.ins` in that directory.

The file `timberborndrawing.sty` will be generated.

In addition to the `timberborndrawing.sty` the file `timberborndrawing.lua` is
also required. 
You have to put them in the same directory as your document or (best) in a `texmf` tree. 


### Simplified version:

* run `l3build unpack` to generate the `.sty` (and the `.lua` files) in
`build/unpacked/`
