module TestPackage2
export hello2, domath2

@static if Sys.iswindows()
  hello2(who::String) = "Hello, $who"

elseif Sys.islinux() || Sys.isapple()
  domath2(x::Number) = x + 5

end

include("precompile_includer.jl")

end
