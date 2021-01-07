# This is loaded conditionally via @require if PyPlot is loaded

using .PyPlot: plt, PyCall

export specialization_plot

get_bystr(@nospecialize(by)) = by === inclusive ? "Inclusive" :
                               by === exclusive ? "Exclusive" : error("unknown ", by)

"""
    methodref, ax = specialization_plot(tinf::InferenceTimingNode; consts::Bool=true, by=inclusive)
    methodref     = specialization_plot(ax, tinf::InferenceTimingNode; kwargs...)

Create a scatter plot comparing:
    - (vertical axis) the inference time for all instances of each Method, as captured by `tinf`;
    - (horizontal axis) the run time cost, as estimated by capturing a `@profile` before calling this function.

Each dot corresponds to a single method. The face color encodes the number of times that method was inferred,
and the edge color corresponds to the fraction of the runtime spent on runtime dispatch (black is 0%, bright red is 100%).
Clicking on a dot prints the method (or location, if inlined) to the REPL, and sets `methodref[]` to
that method.

This depends on PyPlot, which must be loaded first. `ax` is the pyplot axis.
"""
function specialization_plot(ax::PyCall.PyObject, ridata; bystr, consts, markersz=25, linewidth=0.5, t0 = 0.001, interactive::Bool=true, kwargs...)
    methodref = Ref{Union{Method,MethodLoc}}()
    function onclick(event)
        xc, yc = event.xdata, event.ydata
        idx = argmin((log.(rts .+ t0) .- log(xc)).^2 + (log.(its .+ t0) .- log(yc)).^2)
        m = meths[idx]
        methodref[] = m
        println(m, " ($(nspecs[idx]) specializations)")
    end

    meths, rts, its, nspecs, ecols = Union{Method,MethodLoc}[], Float64[], Float64[], Int[], Tuple{Float64,Float64,Float64}[]
    for (m, (rt, trtd, it, nspec)) in ridata
        push!(meths, m)
        push!(rts, rt)
        push!(its, it)
        push!(nspecs, nspec)
        push!(ecols, (rt > 0 ? trtd/rt : 0.0, 0.0, 0.0))
    end
    sp = sortperm(nspecs)
    meths, rts, its, nspecs, ecols = meths[sp], rts[sp], its[sp], nspecs[sp], ecols[sp]

    # Add t0 to each entry to handle times of zero in the log-log plot
    smap = ax.scatter(rts .+ t0, its .+ t0, markersz, nspecs; norm=plt.matplotlib.colors.LogNorm(), edgecolors=ecols, linewidths=linewidth, kwargs...)
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("Run time (self) + $t0 (s)")
    ax.set_ylabel("$bystr inference time + $t0 (s)")
    ax.set_aspect("equal")
    constsmode = consts ? "incl." : "excl."
    plt.colorbar(smap, label = "# specializations ($constsmode consts)", ax=ax)
    if interactive
        ax.get_figure().canvas.mpl_connect("button_press_event", onclick)
    end
    return methodref
end

function specialization_plot(ridata; kwargs...)
    fig, ax = plt.subplots()
    return specialization_plot(ax, ridata; kwargs...), ax
end

function specialization_plot(ax::PyCall.PyObject, tinf::InferenceTimingNode; consts::Bool=true, by=inclusive, kwargs...)
    specialization_plot(ax, runtime_inferencetime(tinf; consts, by); bystr=get_bystr(by), consts, kwargs...)
end
function specialization_plot(tinf::InferenceTimingNode; consts::Bool=true, by=inclusive, kwargs...)
    specialization_plot(runtime_inferencetime(tinf; consts, by); bystr=get_bystr(by), consts, kwargs...)
end
