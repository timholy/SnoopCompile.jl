module PkgD

using PkgC

call_nbits(x::Integer) = PkgC.nbits(x)
call_nbits_integer(x::Integer) = invoke(PkgC.nbits, Tuple{Integer}, x)
map_nbits(list) = map(call_nbits, list)
nbits_list() = map_nbits(Integer[Int8(1), Int16(1)])

call_lacks_methods() = PkgC.lacks_methods()
call_undefined_function() = PkgC.undefined_function()

uses_someconst(x) = x + PkgC.someconst
calls_mytype(x) = PkgC.MyType(x)

# Precompilation
nbits_list()
call_nbits(UInt16(1))
call_nbits_integer(Int8(1))
uses_someconst(1)
calls_mytype(1)
# ones that would error
precompile(call_nbits, (String,))
precompile(call_lacks_methods, ())
precompile(call_undefined_function, ())

end # module PkgD
