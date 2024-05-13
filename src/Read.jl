# Copyright (c) 2020-2024, Bank of Canada
# All rights reserved.

"""
    struct FameRange … end

Range includes a frequency code and two endpoints start and end. This is a type
used by the CHLI library.
"""
struct FameRange
    r_freq::Cint
    r_start::Clonglong
    r_end::Clonglong
end
FameRange() = FameRange(0, 0, 0)
# Base.length(r::FameRange) = (-1 ∈ (r.r_end, r.r_start)) ? 0 : Int64(r.r_end)-Int64(r.r_start)+1



@inline unsafe_read!!(::Val{:precision}, key, name, range, vals) =
    (@fame_call_check(fame_get_precisions,
        (Cint, Cstring, Ptr{FameRange}, Ref{Float64}),
        key, name, range, vals);
    vals)

@inline unsafe_read!!(::Val{:numeric}, key, name, range, vals) =
    (@fame_call_check(fame_get_numerics,
        (Cint, Cstring, Ptr{FameRange}, Ref{Float32}),
        key, name, range, vals);
    vals)

@inline unsafe_read!!(::Val{:boolean}, key, name, range, vals) =
    (@fame_call_check(fame_get_booleans,
        (Cint, Cstring, Ptr{FameRange}, Ref{Int32}),
        key, name, range, vals);
    vals)

@inline function unsafe_read!!(::Val{:string}, key, name, range, vals::Ref{String})
    vals[] = unsafe_read!!(Val(:string), key, name, range, String[""])[1]
end

function unsafe_read!!(::Val{:string}, key, name, range, vals::AbstractVector{String})
    lens = Vector{Cint}(undef, length(vals))
    @fame_call_check(fame_len_strings,
        (Cint, Cstring, Ptr{FameRange}, Ref{Int32}),
        key, name, range, lens)
    # allocate string and make room for the trailing '\0'
    map!(len -> repeat("\0", len + 1), vals, lens)
    @fame_call_check(fame_get_strings,
        (Cint, Cstring, Ptr{FameRange}, Ptr{Ptr{UInt8}}, Ref{Int32}, Ptr{Int32}),
        key, name, range, vals, lens, C_NULL)
    # strip trailing '\0'
    map!((len, val) -> val[1:len], vals, lens, vals)
    return vals
end

# the case where values are dates and so the type is a frequency
@inline function unsafe_read!!(::Val{TY}, key, name, range, vals) where {TY}
    @assert(haskey(fame_freq, TY), "Cannot read data of type $TY.")
    @fame_call_check(fame_get_dates,
        (Cint, Cstring, Ptr{FameRange}, Ref{FameDate}),
        key, name, range, vals)
    vals
end

# the case of namelist.  It's always a scalar
const HNLALL = Int32(-1)
function unsafe_read!!(::Val{:namelist}, key, name, range, vals)
    len = Ref{Cint}(-1)
    @cfm_call_check(cfmnlen,
        (Cint, Cstring, Cint, Ref{Cint}),
        key, name, HNLALL, len)
    # len[] += 1
    vals[] = repeat("\0", len[])
    @cfm_call_check(cfmgtnl,
        (Cint, Cstring, Cint, Ptr{UInt8}, Cint, Ref{Cint}),
        key, name, HNLALL, vals[], len[], len)
    return vals
end

"""
    do_read!(obj::FameObject, db::FameDatabase)

Read data for the given [`FameObject`](@ref) from the given
[`FameDatabase`](@ref). `obj` is modified in place and returned.

A [`FameObject`](@ref) can be created directly, or it could be
returned by [`quick_info`](@ref) or [`listdb`](@ref).
"""
function do_read! end
export do_read!

function do_read!(obj::FameObject{:scalar,FT,FR}, db::FameDatabase) where {FT,FR}
    # number of observations = 0
    # range = CNULL
    unsafe_read!!(Val(FT), db.key, obj.name, C_NULL, obj.data)
    return obj
end

function do_read!(obj::FameObject{:series,FT,FR}, db::FameDatabase) where {FT,FR}
    if obj.first_index[] == FAME_INDEX_NC || obj.last_index[] == FAME_INDEX_NC
        # empty series
        empty!(obj.data)
        return obj
    end
    range = Ref(FameRange(val_to_int(FR, fame_freq), obj.first_index[], obj.last_index[]))
    resize!(obj.data, obj.last_index[] - obj.first_index[] + 1)
    unsafe_read!!(Val(FT), db.key, obj.name, range, obj.data)
    return obj
end


# const HNMVAL = Int32(0) # Normal value; not missing or magic
# const HNCVAL = Int32(1) # Missing NC - Not Computable
# const HNAVAL = Int32(2) # Missing NA - Not Available
# const HNDVAL = Int32(3) # Missing ND - Not Defined
# const HMGVAL = Int32(4) # Magic value; for internal use only

