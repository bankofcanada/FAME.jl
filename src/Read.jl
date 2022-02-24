# Copyright (c) 2020-2022, Bank of Canada
# All rights reserved.

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
    for ind in eachindex(lens)
        vals[ind] = repeat("\0", lens[ind])
    end
    @fame_call_check(fame_get_strings,
        (Cint, Cstring, Ptr{FameRange}, Ptr{Ptr{UInt8}}, Ref{Int32}, Ptr{Int32}),
        key, name, range, vals, lens, C_NULL)
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

function do_read!(fo::FameObject{:scalar,FT,FR}, db::FameDatabase) where {FT,FR}
    # number of observations = 0
    # range = CNULL
    unsafe_read!!(Val(FT), db.key, fo.name, C_NULL, fo.data)
    return fo
end

function do_read!(fo::FameObject{:series,FT,FR}, db::FameDatabase) where {FT,FR}
    if fo.first_index[] == FAME_INDEX_NC || fo.last_index[] == FAME_INDEX_NC
        # empty series
        empty!(fo.data)
        return fo
    end
    range = Ref(FameRange(val_to_int(FR, fame_freq), fo.first_index[], fo.last_index[]))
    resize!(fo.data, fo.last_index[] - fo.first_index[] + 1)
    unsafe_read!!(Val(FT), db.key, fo.name, range, fo.data)
    return fo
end


# const HNMVAL = Int32(0) # Normal value; not missing or magic
# const HNCVAL = Int32(1) # Missing NC - Not Computable
# const HNAVAL = Int32(2) # Missing NA - Not Available
# const HNDVAL = Int32(3) # Missing ND - Not Defined
# const HMGVAL = Int32(4) # Magic value; for internal use only

