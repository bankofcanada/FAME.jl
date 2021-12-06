

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
    for ind = eachindex(lens)
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

function do_read!(fo::FameObject{:scalar,FT,FR},db::FameDatabase) where {FT,FR}
    # number of observations = 0
    # range = CNULL
    unsafe_read!!(Val(FT), db.key, fo.name, C_NULL, fo.data)
    return
end

function do_read!(fo::FameObject{:series,FT,FR},db::FameDatabase) where {FT,FR}
    if fo.first_index[] == FAME_INDEX_NC || fo.last_index[] == FAME_INDEX_NC
        # empty series
        empty!(fo.data)
        return
    end
    range = Ref(FameRange(val_to_int(FR, fame_freq), fo.first_index[], fo.last_index[]))
    resize!(fo.data, fo.last_index[] - fo.first_index[] + 1)
    unsafe_read!!(Val(FT), db.key, fo.name, range, fo.data)
    return
end



# FameDate = FameIndex

# const HNMVAL = Int32(0) # Normal value; not missing or magic
# const HNCVAL = Int32(1) # Missing NC - Not Computable
# const HNAVAL = Int32(2) # Missing NA - Not Available
# const HNDVAL = Int32(3) # Missing ND - Not Defined
# const HMGVAL = Int32(4) # Magic value; for internal use only


# function to_bool(value::Int32)
#     mt = Ref{Int32}(-1)
#     @cfm_call_check(cfmisbm, (Cint, Ref{Cint}), value, mt)
#     if mt.x != HNMVAL
#         return missing
#     else
#         return Bool(value)
#     end
# end


# function to_numeric(value::Float32)
#     mt = Ref{Int32}(-1)
#     @cfm_call_check(cfmisnm, (Cfloat, Ref{Cint}), value, mt)
#     if mt.x != HNMVAL
#         return missing
#     else
#         return value
#     end
# end


# function to_precision(value::Float64)
#     mt = Ref{Int32}(-1)
#     @cfm_call_check(cfmispm, (Cdouble, Ref{Cint}), value, mt)
#     if mt.x != HNMVAL
#         return missing
#     else
#         return value
#     end
# end


# function to_date(value::FameIndex)
#     mt = Ref{Int32}(-1)
#     @fame_call_check(fame_date_missing_type, (Clonglong, Ref{Cint}), value, mt)
#     if mt.x != HNMVAL
#         return missing
#     else
#         return value
#     end
# end


# function to_string(value::String)
#     mt = Ref{Int32}(-1)
#     val = String(strip(value, '\0'))
#     @cfm_call_check(cfmissm, (Cstring, Ref{Cint}), val, mt)
#     if mt.x != HNMVAL
#         return missing
#     else
#         return val
#     end
# end


# function fame_read(db::FameDatabase, name::String)
#     fqi = fame_quick_info(db, name)
#     if isseries(fqi)
#         if (fqi.first != FAME_INDEX_NC) && (fqi.last != FAME_INDEX_NC)
#             range = Ref(FameRange())
#             @fame_call_check(fame_init_range_from_indexes, (Ref{FameRange}, FameFreq, FameIndex, FameIndex),
#                             range, fqi.freq, fqi.first, fqi.last)
#             nobs = Int64(fqi.last) - Int64(fqi.first) + 1
#         else
#             # empty SERIES
#             range = C_NULL
#             nobs = 0
#         end
#     else
#         # reading SCALAR
#         range = C_NULL
#         nobs = 1
#     end
#     if isprecision(fqi)
#         if nobs > 0
#             tmp = Vector{Float64}(undef, nobs)
#             @fame_call_check(fame_get_precisions, (Cint, Cstring, Ptr{FameRange}, Ref{Float64}),
#                 db.key, name, range, tmp)
#             data = [to_precision(x) for x in tmp]
#         else
#             data = Float64[]
#         end
#     elseif isnumeric(fqi)
#         if nobs > 0
#             tmp = Vector{Float32}(undef, nobs)
#             @fame_call_check(fame_get_numerics, (Cint, Cstring, Ptr{FameRange}, Ref{Float32}),
#                 db.key, name, range, tmp)
#             data = [to_numeric(x) for x in tmp]
#         else
#             data = Float32[]
#         end
#     elseif isboolean(fqi)
#         if nobs > 0
#             tmp = Vector{Int32}(undef, nobs)
#             @fame_call_check(fame_get_booleans, (Cint, Cstring, Ptr{FameRange}, Ref{Int32}),
#                 db.key, name, range, tmp)
#             data = [to_bool(x) for x in tmp]
#         else
#             data = Bool[]
#         end
#     elseif isdate(fqi)
#         if nobs > 0
#             tmp = Vector{FameIndex}(undef, nobs)
#             @fame_call_check(fame_get_dates, (Cint, Cstring, Ptr{FameRange}, Ref{FameIndex}),
#                 db.key, name, range, tmp)
#             data = [to_date(x) for x in tmp]
#         else
#             data = FameIndex[]
#         end
#     elseif isstring(fqi)
#         if nobs == 0
#             data = String[]
#         else
#             lens = Vector{Int32}(undef, nobs)
#             @fame_call_check(fame_len_strings, (Cint, Cstring, Ptr{FameRange}, Ref{Int32}),
#                 db.key, name, range, lens)
#             tmp = Vector{String}(undef, nobs)
#             for i = 1:nobs
#                 lens[i] += 1
#                 tmp[i] = repeat(" ", lens[i])
#             end
#             @fame_call_check(fame_get_strings, (Cint, Cstring, Ptr{FameRange}, Ptr{Ptr{UInt8}}, Ref{Int32}, Ptr{Int32}),
#                 db.key, name, range, tmp, lens, C_NULL)
#             data = [to_string(x) for x in tmp]
#         end
#     elseif isnamelist(fqi)
#         len = Ref{Cint}(-1)
#         @cfm_call_check(cfmnlen, (Cint, Cstring, Cint, Ref{Cint}), db.key, name, HNLALL, len)
#         len.x += 1
#         data = repeat(" ", len[])
#         @cfm_call_check(cfmgtnl, (Cint, Cstring, Cint, Ptr{UInt8}, Cint, Ref{Cint}), db.key, name, HNLALL, data, len[], len)
#         data = String[strip(data, ['\0', '{', '}'])]
#     else
#         println("Cannot read data of type $(fqi.type).")
#         return nothing
#     end
#     if fqi.class == HSCALA
#         return FameObject(QuickInfo(name, fqi), data[1])
#     else
#         return FameObject(QuickInfo(name, fqi), data)
#     end
# end
# export fame_read


##################


# export loaddb
# function loaddb(db::FameDatabase, wildcard::String="?", numbobj::Integer=10000, lowerCase::Bool = true)
#     name_transform = lowerCase ? lowercase : identity
#     varlist = listdb(db, wildcard, maxobj=numbobj);
#     return Dict(name_transform(var.name) => fame_read(db, var.name) for var in varlist)
# end

