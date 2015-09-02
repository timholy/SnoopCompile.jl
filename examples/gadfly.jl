# Run this after snoop_on.jl

if !isinteractive()
    error("Because Gadfly uses the display, you must run this interactively")
end

using SnoopCompile

using Gadfly, RDatasets, SnoopCompile
ds1 = dataset("datasets", "iris")
ds2 = dataset("car", "SLID")

SnoopCompile.@snoop "/tmp/gadfly_compiles.csv" begin
           display(plot(ds1, x="SepalLength", y="SepalWidth", Geom.point))
           display(plot(ds2, x="Wages", color="Language", Geom.histogram))
           display(plot(x=collect(1:100), y=sort(rand(100))))
           display(plot([sin, cos], 0, 25))
       end

snoop_off()

data = SnoopCompile.read("/tmp/gadfly_compiles.csv")
pc, discards = SnoopCompile.parcel(data[end:-1:1,2])
SnoopCompile.write(pc, "/tmp/precompile")
