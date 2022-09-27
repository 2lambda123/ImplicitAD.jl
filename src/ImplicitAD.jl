module ImplicitAD

using ForwardDiff
using ReverseDiff
using ChainRulesCore
using LinearAlgebra: factorize

# main function
export implicit_function, implicit_linear_function


# ---------------------------------------------------------------------------

# ------- Unpack/Pack ForwardDiff Dual ------

fd_value(x) = ForwardDiff.value.(x)
fd_partials(x) = reduce(vcat, transpose.(ForwardDiff.partials.(x)))

"""
unpack ForwardDiff Dual return value and derivative.
"""
function unpack_dual(x) 
    xv = fd_value(x)
    dx = fd_partials(x)
    return xv, dx
end

"""
Create a ForwardDiff Dual with value yv, derivatives dy, and Dual type T
"""
pack_dual(yv::AbstractFloat, dy, T) = ForwardDiff.Dual{T}(yv, ForwardDiff.Partials(Tuple(dy)))
pack_dual(yv::AbstractVector, dy, T) = ForwardDiff.Dual{T}.(yv, ForwardDiff.Partials.(Tuple.(eachrow(dy))))

# -----------------------------------------

# ---------- core methods -----------------

struct FJVPTag end

"""
Compute Jacobian vector product b = B*v where B_ij = ∂r_i/∂x_j
"""
function jvp_forward(residual, x, y, v)
    
    # create new seed using v
    xd = pack_dual(x, v, FJVPTag)
    
    # evaluate residual function
    rd = residual(xd, y)  # constant y
    
    # extract partials
    b = fd_partials(rd) 

    return b

end

"""
internal convenience method for when user can provide drdx
"""
function jvp_provide(residual, x, y, v, drdx)
    
    B = drdx(residual, x, y)
    return B*v

end

"""
Compute vector Jacobian product c = B^T v = (v^T B)^T where B_ij = ∂r_i/∂x_j and return c
"""
function vjp_reverse(residual, x, y, v)
    return ReverseDiff.gradient(xtilde -> v' * residual(xtilde, y), x)  # instead of using underlying functions in ReverseDiff just differentiate -v^T * r with respect to x to get -v^T * dr/dx
end

"""
internal convenience method for when user can provide drdx
"""
function vjp_provide(residual, x, y, v, drdx)
    
    B = drdx(residual, x, y)
    return (v'*B)'
    
end


"""
compute A_ij = ∂r_i/∂y_j
"""
function drdy_forward(residual, x, y)
    A = ForwardDiff.jacobian(ytilde -> residual(x, ytilde), y)
    return A
end


"""
Linear solve A x = b  (where A is computed in drdy and b is computed in jvp).
"""
linear_solve(A, b) = A\b

"""
transpose linear solve A^T x = c  (where A is computed in drdy and c is computed in vjp)
"""
transpose_linear_solve(A, b) = (b' / A)'

# -----------------------------------------



# ---------- Overloads for implicit_function ---------

"""
    implicit_function(solve, residual, x; jvp=jvp_forward, vjp=vjp_reverse, drdx=nothing, drdy=drdy_forward, lsolve=linear_solve, tlsolve=transpose_linear_solve)

Make implicit function AD compatible (specifically with ForwardDiff and ReverseDiff).

# Arguments
- `solve::function`: y = solve(x). Solve implicit function (where residual(x, y) = 0) given input x and return states y(x).
- `residual::function`: r = residual(x, y). Return residual given input x and state y.
- `x::vector{float}`: evaluation point.
- `jvp::function`: jvp(residual, x, y, v).  Compute Jacobian vector product b = B*v where B_ij = ∂r_i/∂x_j.  Default is forward mode AD where jacobian is not explicitly constructed.
- `vjp::function`: vjp(residual, x, y, v).  Compute vector Jacobian product c = B^T v = (v^T B)^T where B_ij = ∂r_i/∂x_j and return c  Default is reverse mode AD where Jacobian is not explicitly constructed.
- `drdx::function`: drdx(residual, x, y).  Provide (or compute yourself): ∂r_i/∂x_j.  Not a required function. Default is nothing.  If provided, then jvp and jvp are ignored and explicitly multiplied against this provided Jacobian.
- `drdy::function`: drdy(residual, x, y).  Provide (or compute yourself): ∂r_i/∂y_j.  Default is forward mode AD.
- `lsolve::function`: lsolve(A, b).  Linear solve A x = b  (where A is computed in drdy and b is computed in jvp).  Default is backslash operator.
- `tlsolve::function`: tlsolve(A, b).  Transpose linear solve A^T x = c  (where A is computed in drdy and c is computed in vjp).  Default is forwardslash operator.
"""
function implicit_function(solve, residual, x; jvp=jvp_forward, vjp=vjp_reverse, drdx=nothing, drdy=drdy_forward, lsolve=linear_solve, 
    tlsolve=transpose_linear_solve)
    
    # if dr/dx is provided, then just directly multiply
    if !isnothing(drdx)
        newjvp(residual, x, y, v) = jvp_provide(residual, x, y, v, drdx)
        jvp = newjvp
        newvjp(residual, x, y, v) = vjp_provide(residual, x, y, v, drdx)
        vjp = newvjp
    end

    return implicit_function(solve, residual, x, jvp, vjp, drdy, lsolve, tlsolve)
end



# If no AD, just solve normally.
implicit_function(solve, residual, x, jvp, vjp, drdy, lsolve, tlsolve) = solve(x)



# Overloaded for ForwardDiff inputs, providing exact derivatives using 
# Jacobian vector product.
function implicit_function(solve, residual, x::AbstractVector{<:ForwardDiff.Dual{T}}, jvp, vjp, drdy, lsolve, tlsolve) where {T}

    # unpack dual numbers
    xv, dx = unpack_dual(x) 
    
    # evalute solver
    yv = solve(xv)
    
    # solve for Jacobian-vector product
    b = jvp(residual, xv, yv, -dx)

    # comptue partial derivatives
    A = drdy(residual, xv, yv)
    
    # linear solve
    dy = lsolve(A, b)

    # repack in ForwardDiff Dual
    return pack_dual(yv, dy, T)
end


# Provide a ChainRule rule for reverse mode
function ChainRulesCore.rrule(::typeof(implicit_function), solve, residual, x, jvp, vjp, drdy, lsolve, tlsolve)

    # evalute solver
    y = solve(x)

    # comptue partial derivatives
    A = drdy(residual, x, y)

    function implicit_pullback(dy)
        u = tlsolve(A, dy)
        dx = vjp(residual, x, y, -u)
        return NoTangent(), NoTangent(), NoTangent(), dx, NoTangent(), NoTangent(), NoTangent(), NoTangent(), NoTangent()
    end

    return y, implicit_pullback
end


# register above rule for ReverseDiff
ReverseDiff.@grad_from_chainrules implicit_function(solve, residual, x::TrackedArray, jvp, vjp, drdy, lsolve, tlsolve)
ReverseDiff.@grad_from_chainrules implicit_function(solve, residual, x::AbstractVector{<:TrackedReal}, jvp, vjp, drdy, lsolve, tlsolve)


# ------ linear case ------------

implicit_linear_function(A, b; lsolve=linear_solve, tlsolve=transpose_linear_solve, fact=factorize) = implicit_linear_function(A, b, lsolve, tlsolve, fact)


# If no AD, just solve normally.
implicit_linear_function(A, b, lsolve, tlsolve, fact) = lsolve(A, b)

# catch three cases where one or both contain duals
implicit_linear_function(A::AbstractArray{<:ForwardDiff.Dual{T}}, b::AbstractArray{<:ForwardDiff.Dual{T}}, lsolve, tlsolve, fact) where {T} = linear_dual(A, b, lsolve, fact, T)
implicit_linear_function(A, b::AbstractArray{<:ForwardDiff.Dual{T}}, lsolve, tlsolve, fact) where {T} = linear_dual(A, b, lsolve, fact, T)
implicit_linear_function(A::AbstractArray{<:ForwardDiff.Dual{T}}, b, lsolve, tlsolve, fact) where {T} = linear_dual(A, b, lsolve, fact, T)


# Both A and b contain duals
function linear_dual(A, b, lsolve, fact, T)
    
    # unpack dual numbers (if not dual numbers just returns itself)
    Av = fd_value(A)
    bv = fd_value(b)

    # save factorization since we will perform two linear solves
    Af = fact(Av)
    
    # evalute linear solver
    yv = lsolve(Af, bv)
    
    # extract Partials of b - A * y  i.e., bdot - Adot * y  (since y does not contain duals)
    rhs = fd_partials(b - A*yv)
    
    # solve for new derivatives
    dy = lsolve(Af, rhs)

    # repack in ForwardDiff Dual
    return pack_dual(yv, dy, T)
end


# Provide a ChainRule rule for reverse mode
function ChainRulesCore.rrule(::typeof(implicit_linear_function), A, b, lsolve, tlsolve, fact)

    # save factorization
    Af = fact(A)

    # evalute solver
    y = lsolve(Af, b)

    function implicit_pullback(ybar)
        u = tlsolve(Af, ybar)
        return NoTangent(), -u*y', u, NoTangent(), NoTangent(), NoTangent()
    end

    return y, implicit_pullback
end

# register above rule for ReverseDiff
ReverseDiff.@grad_from_chainrules implicit_linear_function(A::TrackedArray, b, lsolve, tlsolve, fact)
ReverseDiff.@grad_from_chainrules implicit_linear_function(A::AbstractVector{<:TrackedReal}, b, lsolve, tlsolve, fact)
ReverseDiff.@grad_from_chainrules implicit_linear_function(A, b::TrackedArray, lsolve, tlsolve, fact)
ReverseDiff.@grad_from_chainrules implicit_linear_function(A, b::AbstractVector{<:TrackedReal}, lsolve, tlsolve, fact)
ReverseDiff.@grad_from_chainrules implicit_linear_function(A::TrackedArray, b::TrackedArray, lsolve, tlsolve, fact)
ReverseDiff.@grad_from_chainrules implicit_linear_function(A::AbstractVector{<:TrackedReal}, b::AbstractVector{<:TrackedReal}, lsolve, tlsolve, fact)

end
