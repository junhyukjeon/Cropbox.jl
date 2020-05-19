import DataFrames: DataFrame
import Gadfly
import UnicodePlots
import Unitful

extractcolumn(df::DataFrame, n::Symbol) = df[!, n]
extractcolumn(df::DataFrame, n::Expr) = begin
    ts(x) = x isa Symbol ? :(df[!, $(Meta.quot(x))]) : x
    te(x) = @capture(x, f_(a__)) ? :($f($(ts.(a)...))) : x
    #HACK: avoid world age problem for function scope eval
    e = Main.eval(:(df -> @. $(MacroTools.postwalk(te, n))))
    (() -> @eval $e($df))()
end
extractunit(df::DataFrame, n) = unit(eltype(extractcolumn(df, n)))
extractarray(df::DataFrame, n, u) = begin
    #HACK: Gadfly doesn't handle missing properly: https://github.com/GiovineItalia/Gadfly.jl/issues/1267
    coalesce.(deunitfy.(extractcolumn(df, n), u), NaN)
end

findlim(array) = begin
    #HACK: lack of missing support in Gadfly
    a = filter(!isnan, array)
    l = isempty(a) ? 0 : floor(minimum(a))
    u = isempty(a) ? 0 : ceil(maximum(a))
    #HACK: avoid empty range
    l == u ? (l, l+1) : (l, u)
end

label(l, u::Units) = Unitful.isunitless(u) ? "$l" : "$l ($u)"

detectbackend() = begin
    if isdefined(Main, :IJulia) && Main.IJulia.inited
        :Gadfly
    else
        :UnicodePlots
    end
end

plot(df::DataFrame, x, y; name=nothing, kw...) = plot(df, x, [y]; name=[name], kw...)
plot(df::DataFrame, x, y::Vector; kw...) = plot!(nothing, df, x, y; kw...)
plot!(p, df::DataFrame, x, y; name=nothing, kw...) = plot!(p, df, x, [y]; name=[name], kw...)
plot!(p, df::DataFrame, x, y::Vector;
    kind=:scatter,
    title=nothing,
    xlab=nothing, ylab=nothing,
    legend=nothing, name=nothing,
    xlim=nothing, ylim=nothing,
    xunit=nothing, yunit=nothing,
    aspect=nothing,
    backend=nothing,
) = begin
    u(n) = extractunit(df, n)
    isnothing(xunit) && (xunit = u(x))
    isnothing(yunit) && (yunit = Unitful.promote_unit(u.(y)...))

    arr(n, u) = extractarray(df, n, u)
    X = arr(x, xunit)
    Ys = arr.(y, yunit)
    n = length(Ys)

    isnothing(xlim) && (xlim = findlim(X))
    if isnothing(ylim)
        l = findlim.(Ys)
        ylim = (minimum(l)[1], maximum(l)[2])
    end

    #HACK: add newline to ensure clearing (i.e. test summary right after plot)
    xlab = label(isnothing(xlab) ? x : xlab, xunit) * '\n'
    ylab = label(isnothing(ylab) ? "" : ylab, yunit)
    legend = isnothing(legend) ? "" : string(legend)
    name = isnothing(name) ? repeat([nothing], n) : name
    names = [string(isnothing(l) ? t : l) for (t, l) in zip(y, name)]
    title = isnothing(title) ? "" : string(title)

    isnothing(backend) && (backend = detectbackend())
    plot2!(Val(backend), p, X, Ys; kind=kind, title=title, xlab=xlab, ylab=ylab, legend=legend, names=names, xlim=xlim, ylim=ylim, aspect=aspect)
end

plot(df::DataFrame, x, y, z;
    kind=:heatmap,
    title=nothing,
    xlab=nothing, ylab=nothing, zlab=nothing,
    xlim=nothing, ylim=nothing, zlim=nothing,
    xunit=nothing, yunit=nothing, zunit=nothing,
    aspect=nothing,
    backend=nothing,
) = begin
    u(n) = extractunit(df, n)
    isnothing(xunit) && (xunit = u(x))
    isnothing(yunit) && (yunit = u(y))
    isnothing(zunit) && (zunit = u(z))

    arr(n, u) = extractarray(df, n, u)
    X = arr(x, xunit)
    Y = arr(y, yunit)
    Z = arr(z, zunit)

    isnothing(xlim) && (xlim = findlim(X))
    isnothing(ylim) && (ylim = findlim(Y))
    isnothing(zlim) && (zlim = findlim(Z))

    #HACK: add newline to ensure clearing (i.e. test summary right after plot)
    xlab = label(isnothing(xlab) ? x : xlab, xunit) * '\n'
    ylab = label(isnothing(ylab) ? y : ylab, yunit)
    zlab = label(isnothing(zlab) ? z : zlab, zunit)
    title = isnothing(title) ? "" : string(title)

    isnothing(backend) && (backend = detectbackend())
    plot3!(Val(backend), X, Y, Z; kind=kind, title=title, xlab=xlab, ylab=ylab, zlab=zlab, xlim=xlim, ylim=ylim, zlim=zlim, aspect=aspect)
end

plot2!(::Val{:Gadfly}, p, X, Ys; kind, title, xlab, ylab, legend, names, xlim, ylim, aspect) = begin
    n = length(Ys)

    if kind == :line
        geom = Gadfly.Geom.line
    elseif kind == :scatter
        geom = Gadfly.Geom.point
    else
        error("unrecognized plot kind = $kind")
    end

    theme = Gadfly.Theme(
        background_color="white",
        major_label_font_size=10*Gadfly.pt,
        key_title_font_size=9*Gadfly.pt,
    )

    if isnothing(p)
        colors = Gadfly.Scale.default_discrete_colors(n)
        layers = [Gadfly.layer(x=X, y=Ys[i], geom, Gadfly.Theme(default_color=colors[i])) for i in 1:n]
        p = Gadfly.plot(
            Gadfly.Coord.cartesian(xmin=xlim[1], ymin=ylim[1], xmax=xlim[2], ymax=ylim[2], aspect_ratio=aspect),
            Gadfly.Guide.title(title),
            Gadfly.Guide.xlabel(xlab),
            Gadfly.Guide.ylabel(ylab),
            Gadfly.Guide.manual_color_key(legend, names, colors),
            layers...,
            theme,
        )
    else
        #TODO: very hacky approach to append new plots... definitely need a better way
        n0 = length(p.layers)
        colors = Gadfly.Scale.default_discrete_colors(n0 + n)
        #HACK: extend ManualColorKey with new elements
        mck = p.guides[end]
        for (c, l) in zip(colors[n0+1:end], names)
            mck.labels[c] = l
        end
        layers = [Gadfly.layer(x=X, y=Ys[i], geom, Gadfly.Theme(default_color=colors[n0 + i])) for i in 1:n]
        for l in layers
            Gadfly.push!(p, l)
        end
    end
    p
end

plot2!(::Val{:UnicodePlots}, p, X, Ys; kind, title, xlab, ylab, legend, names, xlim, ylim, aspect, width=40, height=15) = begin
    canvas = if get(ENV, "GITHUB_ACTIONS", "false") == "true"
        UnicodePlots.DotCanvas
    else
        UnicodePlots.BrailleCanvas
    end

    if kind == :line
        plot! = UnicodePlots.lineplot!
    elseif kind == :scatter
        plot! = UnicodePlots.scatterplot!
    else
        error("unrecognized plot kind = $kind")
    end

    if isnothing(p)
        a = Float64[]
        !isnothing(aspect) && (width = round(Int, aspect * 2height))
        p = UnicodePlots.Plot(a, a, canvas; title=title, xlabel=xlab, ylabel=ylab, xlim=xlim, ylim=ylim, width=width, height=height)
        UnicodePlots.annotate!(p, :r, legend)
    end
    for (Y, name) in zip(Ys, names)
        plot!(p, X, Y; name=name)
    end
    p
end

plot3!(::Val{:Gadfly}, X, Y, Z; kind, title, xlab, ylab, zlab, xlim, ylim, zlim, aspect) = begin
    if kind == :heatmap
        geom = Gadfly.Geom.rectbin
        data = (x=X, y=Y, color=Z)
    elseif kind == :contour
        geom = Gadfly.Geom.contour(levels=50)
        data = (x=X, y=Y, z=Z)
    else
        error("unrecognized plot kind = $kind")
    end

    theme = Gadfly.Theme(
        background_color="white",
        major_label_font_size=10*Gadfly.pt,
        key_title_font_size=9*Gadfly.pt,
    )

    Gadfly.plot(
        Gadfly.Coord.cartesian(xmin=xlim[1], ymin=ylim[1], xmax=xlim[2], ymax=ylim[2], aspect_ratio=aspect),
        Gadfly.Guide.title(title),
        Gadfly.Guide.xlabel(xlab),
        Gadfly.Guide.ylabel(ylab),
        Gadfly.Guide.colorkey(title=zlab),
        Gadfly.Scale.color_continuous(minvalue=zlim[1], maxvalue=zlim[2]),
        geom,
        theme;
        data...,
    )
end

plot3!(::Val{:UnicodePlots}, X, Y, Z; kind, title, xlab, ylab, zlab, xlim, ylim, zlim, aspect, width=0, height=30) = begin
    if kind == :heatmap
        ;
    elseif kind == :contour
        @warn "unsupported plot kind = $kind"
    else
        error("unrecognized plot kind = $kind")
    end

    arr(A) = sort(unique(A))
    x = arr(X)
    y = arr(Y)
    M = reshape(Z, length(y), length(x))

    offset(a) = a[1]
    xoffset = offset(x)
    yoffset = offset(y)
    scale(a) = (a[end] - offset(a)) / (length(a) - 1)
    xscale = scale(x)
    yscale = scale(y)

    !isnothing(aspect) && (width = round(Int, aspect * height))

    #TODO: support zlim (minz/maxz currentyl fixed in UnicodePlots)
    UnicodePlots.heatmap(M; title=title, xlabel=xlab, ylabel=ylab, zlabel=zlab, xscale=xscale, yscale=yscale, xlim=xlim, ylim=ylim, xoffset=xoffset, yoffset=yoffset, width=width, height=height)
end
