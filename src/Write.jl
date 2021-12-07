

@inline unsafe_write(::Val{:precision}, key, name, range, vals) =
    @fame_call_check(fame_write_precisions,
        (Cint, Cstring, Ptr{FameRange}, Ref{Float64}),
        key, name, range, vals)

@inline unsafe_write(::Val{:numeric}, key, name, range, vals) =
    @fame_call_check(fame_write_numerics,
        (Cint, Cstring, Ptr{FameRange}, Ref{Float32}),
        key, name, range, vals)

@inline unsafe_write(::Val{:boolean}, key, name, range, vals) =
    @fame_call_check(fame_write_booleans,
        (Cint, Cstring, Ptr{FameRange}, Ref{Int32}),
        key, name, range, vals)

@inline function unsafe_write(::Val{TY}, key, name, range, vals) where {TY}
    @assert(haskey(fame_freq, TY), "Cannot write data of type $TY.")
    @fame_call_check(fame_write_dates,
        (Cint, Cstring, Ptr{FameRange}, Cint, Ref{FameDate}),
        key, name, range, val_to_int(TY, fame_freq), vals)
end

@inline function unsafe_write(::Val{:string}, key, name, range, vals::Ref{String})
    tmp = [vals[]]
    @fame_call_check(fame_write_strings,
        (Cint, Cstring, Ptr{FameRange}, Ptr{Ptr{UInt8}}),
        key, name, range, tmp)

end

@inline function unsafe_write(::Val{:string}, key, name, range, vals::AbstractVector{String})
    @fame_call_check(fame_write_strings,
        (Cint, Cstring, Ptr{FameRange}, Ptr{Ptr{UInt8}}),
        key, name, range, vals)
end

@inline function unsafe_write(::Val{:namelist}, key, name, range, vals::Ref{String})
    tmp = uppercase(vals[])
    @cfm_call_check(cfmwtnl,
        (Cint, Cstring, Cint, Ptr{UInt8}),
        key, name, HNLALL, tmp)
end

@inline function do_delete_object(key, name)
    try
        @cfm_call_check(cfmdlob, (Cint, Cstring), key, name)
    catch e
        (e isa HLIError && e.status == HNOOBJ) || rethrow()
    end
end

@inline int_class_type_freq(v::FameObject{CL,TY,FR}) where {CL,TY,FR} =
    (
        val_to_int(CL, fame_class),
        try
            val_to_int(TY, fame_type)
        catch
            val_to_int(TY, fame_freq)
        end,
        val_to_int(FR, fame_freq)
    )

@inline do_new_object(key, fo::FameObject) = begin
    (cl, ty, fr) = int_class_type_freq(fo)
    @cfm_call_check(cfmnwob, (Cint, Cstring, Cint, Cint, Cint, Cint, Cint),
        key, fo.name, cl, fr, ty, fame_basis.daily,
        fame_observed[eltype(fo.data) <: AbstractFloat ? :summed : :undefined])
end

@inline _get_range(::FameObject{:scalar}) = C_NULL
@inline _get_range(fo::FameObject{:series,TY,FR}) where {TY,FR} =
    Ref(FameRange(val_to_int(FR, fame_freq), fo.first_index[], fo.last_index[]))

function do_write(fo::FameObject{CL,FT}, db::FameDatabase) where {CL,FT}
    do_delete_object(db.key, fo.name)
    do_new_object(db.key, fo)
    range = _get_range(fo)
    (CL == :series) && (range[].r_start == FAME_INDEX_NC || range[].r_end == FAME_INDEX_NC) && return
    unsafe_write(Val(FT), db.key, fo.name, range, fo.data)
end

