


"""
    Period

Structure type that holds information about a period. It includes the frequency
and the year:period pair.
"""
struct Period{FREQ}
    year::Int32
    period::Int32
end
Period{FREQ}(ind::Integer) where {FREQ} = 
    iscase(FREQ) ? Period{FREQ}(0, convert(Int32, ind)) :
    # in a scalar freq is undefined and periods are set to 0
    FREQ == :undefined ? Period{FREQ}(0, 0) :
    # in an empty series index is set to INDEX_NC and year,period to -1,-1 
    convert(Int64, ind) == FAME_INDEX_NC ? Period{FREQ}(-1, -1) :
    # otherwise we call fame to convert index to year:period
        let y = Ref{Int32}(-1), p = Ref{Int32}(-1)
            @fame_call_check(fame_index_to_year_period,
                (Cint, Clonglong, Ref{Cint}, Ref{Cint}),
                fame_freq[FREQ], convert(Int64, ind), y, p)
            Period{FREQ}(y[], p[])
        end
Base.show(io::IO, p::Period) = print(io, "$(p.year):$(p.period)")

function FameIndex(p::Period{FREQ})::FameIndex where {FREQ}
    if iscase(FREQ)
        return p.period
    else
        date = Ref{Cint}(-1)
        @fame_call_check(fame_year_period_to_index, (Cint, Ref{Cint}, Cint, Cint), 
            fame_freq[FREQ], date, p.year, p.period)
        return date[]
    end
end

"""
    FameObject

A structured type the represents a Fame scalar or series.
"""
mutable struct FameObject{T}
    name::String
    class::Symbol
    type::Symbol
    freq::Symbol
    first_period::Period
    last_period::Period
    data::T
end

function FameObject(name, cl, ty, fr) 
    # try
        _ty = val_to_symbol(ty, fame_type)
    # catch
        # _ty = val_to_symbol(ty, fame_freq)
    # end
    _cl = val_to_symbol(cl, fame_class)
    _fr = val_to_symbol(fr, fame_freq)
    ElType = _ty == :precision ? Float64 :
             _ty == :numeric ? Float32 :
             _ty == :boolean ? Bool : 
             _ty == :string ? String :
             _ty == :date ? Int32 :
             _ty == :namelist ? String : 
                throw(ArgumentError("Can't handle type $_ty.")) 
    T = _cl == :series ? Vector{ElType} :
        _cl == :scalar ? Ref{ElType} :
            throw(ArgumentError("Can't handle class $cl."))
    return FameObject{T}(name, _cl, _ty, _fr, Period{_fr}(-1), Period{_fr}(-1), T())
end





# """
#     FameDateYMD

# Structure type that holds information about a date. It includes the year,month
# and day.
# """
# struct FameDateYMD
#     year::Int32 
#     month::Int32
#     day::Int32
# end
# Base.show(io::IO, dateYMD::FameDateYMD) = print(io, "$(dateYMD.day)/$(dateYMD.month)/$(dateYMD.year)")


# """
#     QuickInfo

# Structure type that contins the basic meta data about a Fame object.
# It includes name, class, type, frequency, first and last period.
# """
# struct QuickInfo
#     name::String
#     class::FameClass
#     type::FameType
#     freq::FameFreq
#     first_period::Period
#     last_period::Period
# end
# function QuickInfo(n, c, t, f, b::FameIndex, e::FameIndex)
#     fy = Ref{Cint}(-1)
#     fp = Ref{Cint}(-1)
#     ly = Ref{Cint}(-1)
#     lp = Ref{Cint}(-1)
#     if FameClass(c) != HSERIE
#         # when not a SERIES the begining and ending index are set to 0
#         return QuickInfo(n, FameClass(c), FameType(t), FameFreq(f), Period(f, 0, 0), Period(f, 0, 0))
#     elseif b == FameIndex(FAME_INDEX_NC)
#         # when SERIES is empty, the begining and ending index are set to -1
#         return QuickInfo(n, FameClass(c), FameType(t), FameFreq(f), Period(f, -1, -1), Period(f, -1, -1))
#     else
#         return QuickInfo(n, FameClass(c), FameType(t), FameFreq(f), Period(f, b), Period(f, e))
#     end
# end
# function Base.show(io::IO, x::QuickInfo)
#     print(io, x.name * ": ")
#     show(io, x.type)
#     print(io, " "); show(io, x.class)
#     if x.class == HSERIE
#         print(io, " "); show(io, x.freq)
#         print(io, " "); show(io, x.first_period)
#         print(io, " "); show(io, x.last_period)
#     end
# end
# export QuickInfo

# @inline isseries(x::QuickInfo) = isseries(x.class)
# @inline isscalar(x::QuickInfo) = isscalar(x.class)
# @inline iscase(x::QuickInfo) = iscase(x.freq)
# @inline isdate(x::QuickInfo) = isdate(x.type)
# @inline isnumeric(x::QuickInfo) = isnumeric(x.type)
# @inline isprecision(x::QuickInfo) = isprecision(x.type)
# @inline isstring(x::QuickInfo) = isstring(x.type)
# @inline isboolean(x::QuickInfo) = isboolean(x.type)
# @inline isnamelist(x::QuickInfo) = isnamelist(x.type)

# struct FameQI
#     class::FameClass
#     type::FameType
#     freq::FameFreq
#     first::FameIndex
#     last::FameIndex
# end

# QuickInfo(name::String, qi::FameQI) = QuickInfo(name, qi.class, qi.type, qi.freq, qi.first, qi.last)

function fame_quick_info(db::FameDatabase, name::String)
    cl = Ref{Cint}(-1)
    ty = Ref{Cint}(-1)
    fr = Ref{Cint}(-1)
    findex = Ref{Clonglong}(-1)
    lindex = Ref{Clonglong}(-1)
    @fame_call_check(fame_quick_info,
        (Cint, Cstring, Ref{Cint}, Ref{Cint}, Ref{Cint}, Ref{Clonglong}, Ref{Clonglong}),
        db.key, name, cl, ty, fr, findex, lindex)
    fo = FameObject(name, cl[], ty[], fr[])
    fo.first_period = Period{fo.freq}(findex[])
    fo.last_period = Period{fo.freq}(lindex[])
    return fo
end

# @inline isseries(x::FameQI) = isseries(x.class)
# @inline isscalar(x::FameQI) = isscalar(x.class)
# @inline iscase(x::FameQI) = iscase(x.freq)
# @inline isdate(x::FameQI) = isdate(x.type)
# @inline isnumeric(x::FameQI) = isnumeric(x.type)
# @inline isprecision(x::FameQI) = isprecision(x.type)
# @inline isstring(x::FameQI) = isstring(x.type)
# @inline isboolean(x::FameQI) = isboolean(x.type)
# @inline isnamelist(x::FameQI) = isnamelist(x.type)

# """
#     quick_info(db, obj_name)

# Read quick information about the named object from the given database.
# """
# function quick_info(db::FameDatabase, name::String)
#     qi = fame_quick_info(db, name)
#     return QuickInfo(name, qi)
# end
# export quick_info


# const HNLALL = Int32(-1)

# function isfameoname(s::AbstractString) 
#     s = strip(s)
#     if length(s) > 242 || length(s) == 0 return false end
#     c = first(s)
#     if !(isletter(c) || c ∈ ('$', '@')) return false end
#     for c in Iterators.drop(s,1)
#         # NOTE: Base.isnumeric is different from FAME.isnumeric.
#         # Since we don't export our isnumeric, we must be explicit when we want to use the one in Base.
#         if !(isletter(c) || Base.isnumeric(c) || occursin(c, "\$%#@_.")) return false end
#     end
#     # TODO: check if s is a FAME reserved word and if so return false
#     return true
# end
# function isfameoname(ss::AbstractArray{S}) where S <: AbstractString
#     for s in ss 
#         isfameoname(s) || return false
#     end
#     return true
# end

# isnamelist(s::AbstractString) = occursin(',', s) && isfameoname(split(strip(s,['{','}']), ','))

