# frozen_string_literal: true, encoding: ASCII-8BIT

module MTLibcouchbase
    class DesignDocs
        def initialize(bucket, connection, result_meth, **opts)
            @connection = connection
            @result = result_meth
            @bucket = bucket # This reference is required to keep to the connection alive

            opts[:type] = :management
            result(@connection.http("/pools/default/buckets/#{connection.bucket}/ddocs", **opts).then(proc { |resp|
                @ddocs = if resp.body.length > 0
                    JSON.parse(resp.body, Connection::DECODE_OPTIONS)[:rows] || []
                else
                    []
                end
            }))
        end

        def designs
            # Remove '_design/' from the id string
            @ddocs.map { |row| row[:doc][:meta][:id][8..-1] }
        end

        def design(name)
            name = name.to_s
            
            des = nil
            short = nil

            @ddocs.each do |row|
                full = row[:doc][:meta][:id]
                short = full[8..-1]

                if [short, full].include? name
                    des = row[:doc]
                    break
                end
            end

            des ? DesignDoc.new(short, des, @bucket, @connection, @result) : nil
        end
        alias_method :[], :design


        protected


        # This is a proxy to the Bucket#result method
        def result(promise)
            @result.call(promise)
        end
    end

    class DesignDoc
        def initialize(id, row, bucket, connection, result_meth)
            @connection = connection
            @result = result_meth
            @bucket = bucket
            @row = row
            @id = id
        end

        def views
            @row[:json][:views].keys
        end

        def view(name, extended: false, **opts, &blk)
            name = name.to_sym
            entry = @row[:json][:views][name]
            if entry
                @bucket.view(@id, name, **opts, &blk)
            else
                nil
            end
        end
        alias_method :[], :view

        def view_config
            @row[:json][:views]
        end


        protected


        # This is a proxy to the Bucket#result method
        def result(promise)
            @result.call(promise)
        end
    end
end
