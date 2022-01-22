# This is loaded conditionally via @require if PyPlot is loaded

using .PyPlot: plt, PyCall

export pgdsgui

get_bystr(@nospecialize(by)) = by === inclusive ? "Inclusive" :
                               by === exclusive ? "Exclusive" : error("unknown ", by)

"""
    methodref, ax = pgdsgui(tinf::InferenceTimingNode; consts::Bool=true, by=inclusive)
    methodref     = pgdsgui(ax, tinf::InferenceTimingNode; kwargs...)

Create a scatter plot comparing:
    - (vertical axis) the inference time for all instances of each Method, as captured by `tinf`;
    - (horizontal axis) the run time cost, as estimated by capturing a `@profile` before calling this function.

Each dot corresponds to a single method. The face color encodes the number of times that method was inferred,
and the edge color corresponds to the fraction of the runtime spent on runtime dispatch (black is 0%, bright red is 100%).
Clicking on a dot prints the method (or location, if inlined) to the REPL, and sets `methodref[]` to
that method.

`ax` is the pyplot axis of the scatterplot.

!!! compat
    `pgdsgui` depends on PyPlot via the Requires.jl package. You must load both SnoopCompile and PyPlot for this function to be defined.
"""
function pgdsgui(ax::PyCall.PyObject, ridata::AbstractVector{Pair{Union{Method,MethodLoc},PGDSData}}; bystr, consts, markersz=25, linewidth=0.5, t0 = 0.001, interactive::Bool=true, kwargs...)
    methodref = Ref{Union{Method,MethodLoc}}()   # returned to the user for inspection of clicked methods
    function onclick(event)
        xc, yc = event.xdata, event.ydata
        (xc === nothing || yc === nothing) && return
        # Find dot closest to the click position
        idx = argmin((log.(rts .+ t0) .- log(xc)).^2 + (log.(its .+ t0) .- log(yc)).^2)
        m = meths[idx]
        methodref[] = m      # store the clicked method
        println(m, " ($(nspecs[idx]) specializations)")
    end

    # Unpack the inputs into a form suitable for plotting
    meths, rts, its, nspecs, ecols = Union{Method,MethodLoc}[], Float64[], Float64[], Int[], Tuple{Float64,Float64,Float64}[]
    for (m, d) in ridata  # (rt, trtd, it, nspec)
        push!(meths, m)
        push!(rts, d.trun)
        push!(its, d.tinf)
        push!(nspecs, d.nspec)
        push!(ecols, (d.trun > 0 ? d.trtd/d.trun : 0.0, 0.0, 0.0))
    end
    sp = sortperm(nspecs)
    meths, rts, its, nspecs, ecols = meths[sp], rts[sp], its[sp], nspecs[sp], ecols[sp]

    # Plot
    # Add t0 to each entry to handle times of zero in the log-log plot
    smap = ax.scatter(rts .+ t0, its .+ t0, markersz, nspecs; norm=plt.matplotlib.colors.LogNorm(), edgecolors=ecols, linewidths=linewidth, kwargs...)
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("Run time (self) + $t0 (s)")
    ax.set_ylabel("$bystr inference time + $t0 (s)")
    # ax.set_aspect("equal")
    ax.axis("square")
    constsmode = consts ? "incl." : "excl."
    plt.colorbar(smap, label = "# specializations ($constsmode consts)", ax=ax)
    if interactive
        ax.get_figure().canvas.mpl_connect("button_press_event", onclick)
    end
    return methodref
end

function pgdsgui(ax::PyCall.PyObject, args...; consts::Bool=true, by=inclusive, kwargs...)
    pgdsgui(ax, prep_ri(args...; consts, by, kwargs...); bystr=get_bystr(by), consts, kwargs...)
end

function pgdsgui(args...; kwargs...)
    fig, ax = plt.subplots()
    pgdsgui(ax, args...; kwargs...), ax
end

function prep_ri(tinf::InferenceTimingNode, pdata=Profile.fetch(); lidict=lookups, consts, by, kwargs...)
    lookup_firstip!(lookups, pdata)
    return runtime_inferencetime(tinf, pdata; lidict, consts, by)
end

@deprecate specialization_plot pgdsgui
