module TestPackage
export hello, domath

@static if Sys.iswindows()
  hello(who::String) = "Hello, $who"

elseif Sys.islinux()
  domath(x::Number) = x + 5

end

include("precompile_includer.jl")

end
