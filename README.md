# SnoopCompile

[![Build Status](https://travis-ci.org/timholy/SnoopCompile.jl.svg?branch=master)](https://travis-ci.org/timholy/SnoopCompile.jl)

SnoopCompile "snoops" on the Julia compiler, causing it to record the
functions and argument types it's compiling.  From these lists of methods,
you can generate lists of `precompile` directives that may reduce the latency between
loading packages and using them to do "real work."

See the documentation:

[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://timholy.github.io/SnoopCompile.jl/stable)
