module TestPackage3
export hello3, domath3, multiply3

@static if VERSION > v"1.3"
  hello3(who::String) = "Hello, $who"

elseif VERSION > v"1.2"
  domath3(x::Number) = x + 5

else
  multiply3(x::Float64) = x + 6

end

end
