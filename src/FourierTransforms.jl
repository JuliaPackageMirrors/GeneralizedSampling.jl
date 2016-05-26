# ------------------------------------------------------------
# Exact Fourier transforms of Haar scaling function

@doc """
	FourHaarScaling(xi[, J, k])

The Fourier transform of the Haar scaling function on scale `J` and translation `k` evaluated at `xi`.
If not supplied, `J = 0` and `k = 0`.
"""->
function FourHaarScaling(xi::Real)
	if xi == zero(xi)
		return ComplexOne
	else
		return (1.0 - cis(-2.0*pi*xi)) / (2.0*pi*im*xi)
	end
end


# ------------------------------------------------------------
# Fourier transform of Daubechies scaling functions

@doc """
	feval(xi::Float64, C::Vector{Float64}, offset)

*F*ilter *eval*uation at `xi` of the filter `C`, i.e., compute

	sum( C[n]*exp(-2*pi*(offset+n)*xi) )
"""->
function feval(xi::Float64, C::Vector{Float64}, offset::Integer)
	y = ComplexZero
	for n in 1:length(C)
		@inbounds y += C[n]*cis(-twoπ*(offset+n)*xi)
	end
	return y
end

@doc """
	FourDaubScaling(xi, C [, p]; ...)

The Fourier transform of the Daubechies scaling function with filter `C` evaluated at `xi`. 
`p` is the lower bound of `C`'s support minus 1, which by default is 0.

The function is computed as an 'infinite' product;
to control this there are optional arguments:

- `prec`: Include factors that are numerically smaller than 1-prec.
- `maxcount`: The maximum number of factors.
"""->
function FourDaubScaling( xi::Real, C::Vector{Float64}, p::Integer=0; prec=SMALL_PREC, maxcount=100)
	# TODO: Move these checks to vector version?
	# TODO: Assertions in macro?
	@assert isapprox(sum(C), 1.0)
	@assert prec >= SMALL_PREC
	@assert maxcount >= 1

	const almost1 = 1.0 - prec
	const half = 0.5
	Y = ComplexOne
	count = 1
	while count <= maxcount
		xi *= 0.5
		y = feval(xi, C, p)
		Y *= y

		# Convergence check: |y(xi) - 1| is small for small xi. But y is
		# exactly 1 in all even integers, so prevent premature exit
		if abs(xi) <= half
			abs(y) >= almost1 && break
			count += 1
		end
	end

	return Y
end

# TODO: method w/o J and k?
function FourDaubScaling( xi, p::Integer, J::Integer=0, k::Integer=0; offset::Integer=-p, args... )
	C = coef( ifilter(p) )
	scale!(C, 1/sum(C))
	FourDaubScaling( xi, C, J, k; offset=offset, args... )
end


@doc """
	FourScalingFunc( xi, wavename, J=0, k=0; ... )

Compute the Fourier transform at `xi` of the scaling function `wavename` with
scale `J` and translation `k`.

Optional arguments are passed to the Fourier transform of `wavename` (if relevant).
"""->
function FourScalingFunc( xi, wavename::AbstractString, J::Integer=0, k::Integer=0; args... )
	@assert J >= 0 "Scale must be a non-negative integer"

	if ishaar(wavename)
		return FourHaarScaling(xi, J, k)
	elseif isdaubechies(wavename)
		# TODO: offset as an argument to this function?
		return FourDaubScaling(xi, van_moment(wavename), J, k; args...)
	else
		error("Fourier transform for this wavelet is not implemented")
	end

end


# ------------------------------------------------------------------------
# Fourier transform of Daubechies boundary wavelets

@doc """
	UVmat(F::BoundaryFilter) -> Matrix, Matrix

Return the matrices `U` and `V` used in `FourDaubScaling` for boundary scaling functions.
"""->
function UVmat(B::BoundaryFilter)
	const vm = van_moment(B)

	UV = zeros(Complex{Float64}, vm, 3*vm-1)

	for i in 1:vm
		@inbounds UV[i, 1:vm+2*i-1] = bfilter(B, i-1) / sqrt2
	end

	return UV[:,1:vm], UV[:,vm+1:end]
end

@doc """
	FourDaubScaling( xi, p [, J], side::Char; args... ) -> Matrix

The Fourier transform at `xi` of the Daubechies boundary scaling function with `p` vanishing moments at scale `J` at the left or right `side` ('L' or 'R').

The output is an `p`-by-`length(xi)` matrix where column `j` holds the Fourier transform of the `p` boundary functions at `xi[j]`.
"""->
function FourDaubScaling{T<:Real}( xi::AbstractVector{T}, p::Integer, side::Char; maxcount=40 )
	# TODO: Check the phaseshifts of the interior functions
	# TODO: Filters of the interior functions
	@assert 1 <= maxcount <= 100
	#=
	- F is a vector with the Fourier transforms of the boundary scaling
	functions at the current xi
	- F0 is F at the zero vector
	- phihat is the Fourier transform of the internal scaling function
	at the current xi (with different phaseshifts)

	For large j,
	F(xi) \approx U^j*F0 + sum_{l=0}^{j-1} U^l*V*phihat( xi/2^{l+1} )
	where U & V are from UVmat
	=#

	const U, V = UVmat(bfilter(p, side))
	C = coef(ifilter(p, true))
	scale!(C, 1/sum(C))

	const F0 = complex( (eye(U) - U) \ vec(sum(V,2)) )

	# ----------------------------------------
	# Precompute U^l and U^l*V

	Upower = Dict{Int, Matrix{Complex{Float64}}}()
	sizehint!(Upower, maxcount)
	Upower[0] = eye(U)

	UpowerV = Dict{Int, Matrix{Complex{Float64}}}()
	sizehint!(UpowerV, maxcount)
	UpowerV[0] = V

	for l in 1:maxcount
		Upower[l] = U*Upower[l-1]
		UpowerV[l] = U*UpowerV[l-1]
	end

	# ----------------------------------------

	const Nxi = length(xi)
	Y = Array{Complex{Float64}}(p, Nxi)

	# Arrays with temporary results
	F = Array{Complex{Float64}}(p)
	phi_phase = collect(( side == 'L' ? -(p:1.0:3*p-2) : 1+(p:1.0:3*p-2) ))
	scale!(phi_phase, twoπ)
	Nphihat = length(phi_phase)
	phihat = Array{Complex{Float64}}(Nphihat)

	for nxi in 1:Nxi
		fill!(F, ComplexZero)

		current_xi = xi[nxi]
		for l in 0:maxcount-1
			current_xi *= 0.5
			internal = FourDaubScaling(current_xi, C, -p)
			for m in 1:Nphihat
				@inbounds phihat[m] = internal*cis( phi_phase[m]*current_xi )
			end

			# F = F + U^l*V*phihat
			BLAS.gemv!('N', ComplexOne, UpowerV[l], phihat, ComplexOne, F)

			# TODO: Test for convergence after each pass through the loop?
			# http://julialang.org/blog/2013/09/fast-numeric for |F-Fold|^2
		end
		# F = F + U^maxcount*F0
		BLAS.gemv!('N', ComplexOne, Upower[maxcount], F0, ComplexOne, F)

		Y[:,nxi] = F
	end

	return Y
end


# ------------------------------------------------------------
# Dilation and translation. 

@vectorize_1arg Real FourHaarScaling

function FourHaarScaling(xi::Real, J::Integer)
	sqrt(2.0^(-J)) * FourHaarScaling(2.0^(-J)*xi)
end

function FourHaarScaling(xi::Real, J::Integer, k::Integer)
	cis( -twoπ*2.0^(-J)*k*xi ) * FourHaarScaling(xi, J)
end

function FourHaarScaling{T<:Real}( xi::AbstractArray{T}, J::Integer)
	# TODO: Save 2^-J and do above calculations explicitly?
	Y = Array{Complex{Float64}}(size(xi))
	for idx in eachindex(xi)
		@inbounds Y[idx] = FourHaarScaling( xi[idx], J )
	end

	return Y
end

function FourHaarScaling{T<:Real}( xi::AbstractArray{T}, J::Integer, k::Integer)
	Y = Array{Complex{Float64}}(size(xi))
	for idx in eachindex(xi)
		@inbounds Y[idx] = FourHaarScaling( xi[idx], J, k )
	end

	return Y
end


#=
function FourDaubScaling(xi::Real, C::Vector{Float64}, J::Integer; args...)
	sqrt(2.0^(-J)) * FourDaubScaling(2.0^(-J)*xi, C; args...)
end

function FourDaubScaling(xi::Real, C::Vector{Float64}, J::Integer, k::Integer; args...)
	cis( -2.0*pi*2.0^(-J)*k*xi ) * FourDaubScaling(xi, C, J; args...)
end
=#

function FourDaubScaling( xi::AbstractArray{Float64}, C::Vector{Float64}; offset::Integer=-div(length(C),2), args... )
	Y = Array{Complex{Float64}}(size(xi))
	for idx in eachindex(xi)
		@inbounds Y[idx] = FourDaubScaling( xi[idx], C, offset; args... )
	end

	return Y
end

function FourDaubScaling{T<:Real}( xi::AbstractArray{T}, C::Vector{Float64}, J::Integer; offset::Integer=-div(length(C),2), args... )
	dilation = 2.0^(-J)
	scale_factor = sqrt(dilation)
	Y = Array{Complex{Float64}}(size(xi))
	for idx in eachindex(xi)
		@inbounds Y[idx] = scale_factor*FourDaubScaling( dilation*xi[idx], C, offset; args... )
	end

	return Y
end

function FourDaubScaling{T<:Real}( xi::AbstractArray{T}, C::Vector{Float64}, J::Integer, k::Integer; offset::Integer=-div(length(C),2), args... )
	dilation = 2.0^(-J)
	scale_factor = sqrt(dilation)
	Y = Array{Complex{Float64}}(size(xi))
	for idx in eachindex(xi)
		@inbounds Y[idx] = cis(-twoπ*dilation*k*xi[idx]) * scale_factor * FourDaubScaling( dilation*xi[idx], C, offset; args... )
	end

	return Y
end


function FourDaubScaling( xi, p::Integer, side::Char, J::Integer; args... )
	@assert J >= 0

	xi *= 2.0^(-J)
	y = FourDaubScaling(xi, p, side; args...)
	scale!( y, sqrt(2.0^(-J)) )

	return y
end

