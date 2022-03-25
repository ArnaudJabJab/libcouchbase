# frozen_string_literal: true, encoding: ASCII-8BIT

module MTLibcouchbase; end;
class MTLibcouchbase::SubdocRequest

    def initialize(key, quiet, bucket: nil, exec_opts: nil)
        @key = key.to_s
        raise ArgumentError.new("invalid document key #{key.inspect}") unless @key.length > 0
        @refs = []
        @mode = nil
        @quiet = quiet
        @specs = []
        @ignore = []

        @bucket = bucket
        @exec_opts = exec_opts
    end

    attr_reader :mode, :key, :ignore

    # Internal use only
    def to_specs_array
        return @mem if @mem # effectively freezes this object
        number = @specs.length
        @mem = FFI::MemoryPointer.new(::MTLibcouchbase::Ext::SDSPEC, number, false)
        @specs.each_with_index do |spec, index|
            struct_bytes = spec.to_ptr.get_bytes(0, ::MTLibcouchbase::Ext::SDSPEC.size) # (offset, length)
            @mem[index].put_bytes(0, struct_bytes) # (offset, byte_string)
        end
        @specs = nil
        [@mem, number]
    end

    # Internal use only
    def free_memory
        @refs = nil
        @mem = nil
    end

    # When not used in block form
    def execute!(**opts)
        opts = @exec_opts.merge(opts)
        @exec_opts = nil
        bucket = @bucket
        @bucket = nil
        bucket.subdoc_execute!(self, **opts)
    end


    # =========
    #  Lookups
    # =========

    [ :get, :exists, :get_count ].each do |cmd|
        command = :"sdcmd_#{cmd}"
        define_method cmd do |path, quiet: nil, **opts|
            quiet = @quiet if quiet.nil?
            new_spec(quiet, path, command, :lookup)
            self
        end
    end
    alias_method :exists?, :exists


    # ===========
    #  Mutations
    # ===========

    def remove(path, quiet: nil, **opts)
        quiet = @quiet if quiet.nil?
        new_spec(quiet, path, :sdcmd_remove, :mutate)
        self
    end

    [
        :dict_add, :dict_upsert, :array_add_first, :array_add_last, :array_add_unique, :counter
    ].each do |cmd|
        command = :"sdcmd_#{cmd}"
        define_method cmd do |path, value, create_intermediates: true, **opts|
            spec = new_spec(false, path, command, :mutate, create_intermediates)
            set_value(spec, value)
            self
        end
    end

    [
        :replace, :array_insert
    ].each do |cmd|
        command = :"sdcmd_#{cmd}"
        define_method cmd do |path, value, **opts|
            spec = new_spec(false, path, command, :mutate, false)
            set_value(spec, value)
            self
        end
    end


    protected


    # http://docs.couchbase.com/sdk-api/couchbase-c-client-2.8.2/group__lcb-subdoc.html#ga53e89dd6b480e81b82fb305d04d92e18
    def new_spec(quiet, path, cmd, mode, create_intermediates = false)
        @mode ||= mode
        raise "unable to perform #{cmd} as mode is currently #{@mode}" if @mode != mode

        spec = ::MTLibcouchbase::Ext::SDSPEC.new
        spec[:sdcmd] = ::MTLibcouchbase::Ext::SUBDOCOP[cmd]
        spec[:options] = ::MTLibcouchbase::Ext::SDSPEC::MKINTERMEDIATES if create_intermediates

        loc = path.to_s
        str = ref(loc)
        spec[:path][:type] = :kv_copy
        spec[:path][:contig][:bytes] = str
        spec[:path][:contig][:nbytes] = loc.bytesize

        @ignore << quiet
        @specs << spec
        spec
    end

    # http://docs.couchbase.com/sdk-api/couchbase-c-client-2.8.2/group__lcb-subdoc.html#ga61009762f6b23ae2a9685ddb888dc406
    def set_value(spec, value)
        # Create a JSON version of the value.
        #  We throw it into an array so strings and numbers etc are valid, then we remove the array.
        val = [value].to_json[1...-1]
        str = ref(val)
        spec[:value][:vtype] = :kv_copy
        spec[:value][:u_buf][:contig][:bytes] = str
        spec[:value][:u_buf][:contig][:nbytes] = val.bytesize
        value
    end

    # We need to hold a reference to c-strings so they are not GC'd
    def ref(string)
        str = ::FFI::MemoryPointer.from_string(string)
        @refs << str
        str
    end
end
