module TestPackage3
export hello2, domath2, multiply3

@static if VERSION > v"1.3"
  hello3(who::String) = "Hello, $who"

elseif VERSION > v"1.0"
  domath3(x::Number) = x + 5

else
  multiply3(x::Float64) = x + 6

end
include("precompile_includer.jl")

end
