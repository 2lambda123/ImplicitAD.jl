# explicit unsteady
function jvp(perform_step, yprevd, t, tprev, xd, p)

    # evaluate residual function
    yd = perform_step(yprevd, t, tprev, xd, p)  # constant y

    # extract partials
    return fd_partials(yd)
end

# implicit unsteady
function jvp(residual, y, yprevd, t, tprev, xd, p)

    # evaluate residual function
    rd = residual(y, yprevd, t, tprev, xd, p)  # constant y

    # extract partials
    b = -fd_partials(rd)

    return b
end


# explicit unsteady
function vjp(perform_step, yprev, t, tprev, x, p, v)
    return ReverseDiff.gradient((yprevtilde, xtilde) -> v' * perform_step(yprevtilde, t, tprev, xtilde, p), (yprev, x))
end

# implicit unsteady
function vjp(residual, y, yprev, t, tprev, x, p, v)
    return ReverseDiff.gradient((yprevtilde, xtilde) -> v' * residual(y, yprevtilde, t, tprev, xtilde, p), (yprev, x))
end


# implicit unsteady
function drdy_forward(residual, y::AbstractVector, yprev, t, tprev, x, p)
    A = ForwardDiff.jacobian(ytilde -> residual(ytilde, yprev, t, tprev, x, p), y)
    return A
end

function drdy_forward(residual, y::Number, yprev, t, tprev, x, p)  # 1D case
    A = ForwardDiff.derivative(ytilde -> residual(ytilde, yprev, t, tprev, x, p), y)
    return A
end



# ------ Overloads for explicit_unsteady ----------

"""
    explicit_unsteady(solve, residual, x, p=(); drdy=drdy_forward, lsolve=linear_solve)

Make an explicit time-marching analysis AD compatible (specifically with ForwardDiff and
ReverseDiff).

# Arguments:
 - `solve::function`: function `y, t = solve(x, p)`.  Perform a time marching analysis,
    and return the matrix `y = [y[1] y[2] y[3] ... y[N]] where `y[i]` is the state vector at time step `i` (a rows is a state, a columms is a timesteps)
    and vector t = [t[1], t[2], t[3] ... t[N]]` where `t[i]` is the corresponding time,
    for input variables `x`, and fixed variables `p`.
 - `perform_step::function`: Either `y[i] = perform_step(y[i-1], t[i], t[i-1], x, p)` or
    in-place `perform_step!(y[i], y[i-1], t[i], t[i-1], x, p)`. Set the next set of state
    variables `y[i]` (scalar or vector), given the previous state `y[i-1]` (scalar or vector),
    current time `t[i]`, previous time `t[i-1]`, variables `x` (vector), and fixed parameters `p` (tuple).
 - `x`: evaluation point
 - `p`: fixed parameters, default is empty tuple.
"""
function explicit_unsteady(solve, perform_step, x, p=())

    # ---- check for in-place version and wrap as needed -------
    new_perform_step = perform_step
    if applicable(perform_step, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)  # in-place

        function explicit_perform_step_wrap(yprevw, tw, tprevw, xw, pw)  # wrap perform_step function in a explicit form for convenience and ensure type of r is appropriate
            T = promote_type(eltype(yprevw), typeof(tw), typeof(tprevw), eltype(xw))
            yw = zeros(T, length(yprevw))  # match type of input variables
            perform_step(yw, yprevw, tw, tprevw, xw, pw)
            return yw
        end
        new_perform_step = explicit_perform_step_wrap
    end

    return _explicit_unsteady(solve, new_perform_step, x, p)
end

# If no AD, just solve normally.
_explicit_unsteady(solve, perform_step, x, p) = solve(x, p)


# Overloaded for ForwardDiff inputs, providing exact derivatives using Jacobian vector product.
function _explicit_unsteady(solve, perform_step, x::AbstractVector{<:ForwardDiff.Dual{T}}, p) where {T}

    # evaluate solver
    xv = fd_value(x)
    yv, tv = solve(xv, p)

    # get solution dimensions
    ny, nt = size(yv)

    # initialize output
    yd = similar(yv, ForwardDiff.Dual{T}, ny, nt)

    # --- Initial Time Step --- #

    # solve for Jacobian-vector products
    @views ydot = jvp(perform_step, yv[:, 1], tv[1], tv[1], x, p)

    # # repack in ForwardDiff Dual
    @views yd[:, 1] = pack_dual(yv[:, 1], ydot, T)

    # --- Additional Time Steps --- #

    for i = 2:nt

        # solve for Jacobian-vector product
        @views ydot = jvp(perform_step, yd[:, i-1], tv[i], tv[i-1], x, p)

        # repack in ForwardDiff Dual
        @views yd[:, i] = pack_dual(yv[:, i], ydot, T)

    end

    return yd, tv
end


# ReverseDiff needs single array output so unpack before returning to user
_explicit_unsteady(solve, perform_step, x::ReverseDiff.TrackedArray, p) = eu_unpack_reverse(solve, perform_step, x, p)
_explicit_unsteady(solve, perform_step, x::AbstractVector{<:ReverseDiff.TrackedReal}, p) = eu_unpack_reverse(solve, perform_step, x, p)

# just declaring dummy function for below
function _explicit_unsteady_reverse(solve, perform_step, x, p) end

# unpack for user
function eu_unpack_reverse(solve, perform_step, x, p)
    yt = _explicit_unsteady_reverse(solve, perform_step, x, p)
    return yt[1:end-1, :], yt[end, :]
end


# Provide a ChainRule rule for reverse mode
function ChainRulesCore.rrule(::typeof(_explicit_unsteady_reverse), solve, perform_step, x, p)

    # evaluate solver
    yv, tv = solve(x, p)

    # get solution dimensions
    ny, nt = size(yv)

    # create local copy of the output to guard against values getting overwritten
    yv = copy(yv)
    tv = copy(tv)

    function pullback(ytbar)

        @views ybar = ytbar[1:end-1, :]

        if nt > 1

            # --- Final Time Step --- #
            @views λ = ybar[:, nt]
            @views Δybar, Δxbar = vjp(perform_step, yv[:, nt-1], tv[nt], tv[nt-1], x, p, λ)
            xbar = Δxbar
            @views ybar[:, nt-1] += Δybar

            # --- Additional Time Steps --- #
            for i = nt-1:-1:2
                @views λ = ybar[:, i]
                @views Δybar, Δxbar = vjp(perform_step, yv[:, i-1], tv[i], tv[i-1], x, p, λ)
                xbar += Δxbar
                @views ybar[:, i-1] += Δybar
            end

            # --- Initial Time Step --- #
            @views λ = ybar[:, 1]
            @views Δybar, Δxbar = vjp(perform_step, yv[:, 1], tv[1], tv[1], xbar, p, λ)
            xbar += Δxbar

        else

            # --- Initial Time Step --- #
            @views λ = ybar[:, 1]
            @views Δybar, Δxbar = vjp(perform_step, yv[:, 1], tv[1], tv[1], xbar, p, λ)
            xbar = Δxbar

        end

        return NoTangent(), NoTangent(), NoTangent(), xbar, NoTangent()
    end

    return [yv; tv'], pullback
end

# register above rule for ReverseDiff
ReverseDiff.@grad_from_chainrules _explicit_unsteady_reverse(solve, perform_step, x::TrackedArray, p)
ReverseDiff.@grad_from_chainrules _explicit_unsteady_reverse(solve, perform_step, x::AbstractVector{<:TrackedReal}, p)


# ------ Overloads for implicit_unsteady ----------

"""
    implicit_unsteady(solve, residual, x, p=(); drdy=drdy_forward, lsolve=linear_solve)

Make a implicit time-marching analysis AD compatible (specifically with ForwardDiff and
ReverseDiff).

# Arguments:
- `solve::function`: function `y, t = solve(x, p)`.  Perform a time marching analysis,
    and return the matrix `y = [y[1] y[2] y[3] ... y[N]] where `y[i]` is the state vector at time step `i` (a rows is a state, a columms is a timesteps)
    and vector t = [t[1], t[2], t[3] ... t[N]]` where `t[i]` is the corresponding time,
    for input variables `x` and fixed variables `p`.
 - `residual::function`: Either `r[i] = residual(y[i], y[i-1], t[i], t[i-1], x, p)` or
    in-place `residual!(r[i], y[i], y[i-1], t[i], t[i-1], x, p)`. Set current residual
    `r[i]` (scalar or vector), given current state `y[i]` (scalar or vector),
    previous state `y[i-1]` (scalar or vector),
    current and preivous time variables `t[i]` and `t[i-1]`,
    `x` (vector), and fixed parameters `p` (tuple).
 - `x`: evaluation point
 - `p`: fixed parameters, default is empty tuple.
 - `drdy`: drdy(residual, y, x, p). Provide (or compute yourself): ∂ri/∂yj.  Default is
    forward mode AD.
 - `lsolve::function`: `lsolve(A, b)`. Linear solve `A x = b` (where `A` is computed in
    `drdy` and `b` is computed in `jvp`, or it solves `A^T x = c` where `c` is computed
    in `vjp`). Default is backslash operator.
"""
function implicit_unsteady(solve, residual, x, p=(); drdy=drdy_forward, lsolve=linear_solve)

    # ---- check for in-place version and wrap as needed -------
    new_residual = residual
    if applicable(residual, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)  # in-place

        function unsteady_residual_wrap(yw, yprevw, tw, tprevw, xw, pw)  # wrap residual function in a explicit form for convenience and ensure type of r is appropriate
            T = promote_type(typeof(tw), typeof(tprevw), eltype(yw), eltype(yprevw), eltype(xw))
            rw = zeros(T, length(yw))  # match type of input variables
            residual(rw, yw, yprevw, tw, tprevw, xw, pw)
            return rw
        end
        new_residual = unsteady_residual_wrap
    end

    return _implicit_unsteady(solve, new_residual, x, p, drdy, lsolve)
end

# If no AD, just solve normally.
_implicit_unsteady(solve, residual, x, p, drdy, lsolve) = solve(x, p)

# Overloaded for ForwardDiff inputs, providing exact derivatives using Jacobian vector product.
function _implicit_unsteady(solve, residual, x::AbstractVector{<:ForwardDiff.Dual{T}}, p, drdy, lsolve) where {T}

    # evaluate solver
    xv = fd_value(x)
    yv, tv = solve(xv, p)

    # get solution dimensions
    ny, nt = size(yv)

    # initialize output
    yd = similar(yv, ForwardDiff.Dual{T}, ny, nt)

    # --- Initial Time Step --- #

    # solve for Jacobian-vector products
    @views b = jvp(residual, yv[:, 1], yv[:, 1], tv[1], tv[1], x, p)

    # compute partial derivatives
    @views A = drdy(residual, yv[:, 1], yv[:, 1], tv[1], tv[1], xv, p)

    # linear solve
    ydot = lsolve(A, b)

    # # repack in ForwardDiff Dual
    @views yd[:, 1] = pack_dual(yv[:, 1], ydot, T)

    # --- Additional Time Steps --- #

    for i = 2:nt

        # solve for Jacobian-vector product
        @views b = jvp(residual, yv[:, i], yd[:, i-1], tv[i], tv[i-1], x, p)

        # compute partial derivatives
        @views A = drdy(residual, yv[:, i], yv[:, i-1], tv[i], tv[i-1], xv, p)

        # linear solve
        ydot = lsolve(A, b)

        # repack in ForwardDiff Dual
        @views yd[:, i] = pack_dual(yv[:, i], ydot, T)

    end

    return yd, tv
end

# ReverseDiff needs single array output so unpack before returning to user
_implicit_unsteady(solve, residual, x::ReverseDiff.TrackedArray, p, drdy, lsolve) = iu_unpack_reverse(solve, residual, x, p, drdy, lsolve)
_implicit_unsteady(solve, residual, x::AbstractVector{<:ReverseDiff.TrackedReal}, p, drdy, lsolve) = iu_unpack_reverse(solve, residual, x, p, drdy, lsolve)

# just declaring dummy function for below
function _implicit_unsteady_reverse(solve, residual, x, p, drdy, lsolve) end

# unpack for user
function iu_unpack_reverse(solve, residual, x, p, drdy, lsolve)
    yt = _implicit_unsteady_reverse(solve, residual, x, p, drdy, lsolve)
    return yt[1:end-1, :], yt[end, :]
end


# Provide a ChainRule rule for reverse mode
function ChainRulesCore.rrule(::typeof(_implicit_unsteady_reverse), solve, residual, x, p, drdy, lsolve)

    # evaluate solver
    yv, tv = solve(x, p)

    # get solution dimensions
    ny, nt = size(yv)

    # create local copy of the output to guard against values getting overwritten
    yv = copy(yv)
    tv = copy(tv)

    function pullback(ytbar)

        @views ybar = ytbar[1:end-1, :]

        if nt > 1

            # --- Final Time Step --- #
            @views A = drdy(residual, yv[:, nt], yv[:, nt-1], tv[nt], tv[nt-1], x, p)
            @views λ = lsolve(A', ybar[:, nt])
            @views Δybar, Δxbar = vjp(residual, yv[:, nt], yv[:, nt-1], tv[nt], tv[nt-1], x, p, -λ)
            xbar = Δxbar
            @views ybar[:, nt-1] += Δybar

            # --- Additional Time Steps --- #
            for i = nt-1:-1:2
                @views A = drdy(residual, yv[:, i], yv[:, i-1], tv[i], tv[i-1], x, p)
                @views λ = lsolve(A', ybar[:, i])
                @views Δybar, Δxbar = vjp(residual, yv[:, i], yv[:, i-1], tv[i], tv[i-1], x, p, -λ)
                xbar += Δxbar
                @views ybar[:, i-1] += Δybar
            end

            # --- Initial Time Step --- #
            @views A = drdy(residual, yv[:, 1], yv[:, 1], tv[1], tv[1], x, p)
            @views λ = lsolve(A', ybar[:, 1])
            @views Δybar, Δxbar = vjp(residual, yv[:, 1], yv[:, 1], tv[1], tv[1], xbar, p, -λ)
            xbar += Δxbar

        else

            # --- Initial Time Step --- #
            @views A = drdy(residual, yv[:, 1], yv[:, 1], tv[1], tv[1], x, p)
            @views λ = lsolve(A', ybar[:, 1])
            @views Δybar, Δxbar = vjp(residual, yv[:, 1], yv[:, 1], tv[1], tv[1], xbar, p, -λ)
            xbar = Δxbar

        end

        return NoTangent(), NoTangent(), NoTangent(), xbar, NoTangent(), NoTangent(), NoTangent()
    end

    return [yv; tv'], pullback
end

# register above rule for ReverseDiff
ReverseDiff.@grad_from_chainrules _implicit_unsteady_reverse(solve, residual, x::TrackedArray, p, drdy, lsolve)
ReverseDiff.@grad_from_chainrules _implicit_unsteady_reverse(solve, residual, x::AbstractVector{<:TrackedReal}, p, drdy, lsolve)