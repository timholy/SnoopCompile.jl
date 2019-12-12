# SnoopCompile

[![Build Status](https://travis-ci.org/timholy/SnoopCompile.jl.svg?branch=master)](https://travis-ci.org/timholy/SnoopCompile.jl)

SnoopCompile observes the Julia compiler, causing it to record the
functions and argument types it's compiling.  From these lists of methods,
you can generate lists of `precompile` directives that may reduce the latency between
loading packages and using them to do "real work."

See the documentation:

[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://timholy.github.io/SnoopCompile.jl/stable)

## Packages that use SnoopCompile

Quite a few packages have used SnoopCompile to reduce startup latency, and some have preserved their scripts which may serve as an example to other users:

- MatLang ([SnoopFile Folder](https://github.com/juliamatlab/MatLang/tree/master/deps/SnoopCompile) and [source file](https://github.com/juliamatlab/MatLang/blob/85640e269e902b6fb68ad254f0b939e1ffb47e7d/src/MatLang.jl#L26)).
