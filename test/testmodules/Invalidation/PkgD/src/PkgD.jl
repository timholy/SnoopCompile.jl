module PkgD

using PkgC

call_nbits(x::Integer) = PkgC.nbits(x)
map_nbits(list) = map(call_nbits, list)
nbits_list() = map_nbits(Integer[Int8(1), Int16(1)])

nbits_list()

end # module PkgD
