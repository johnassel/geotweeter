class StreamRequest extends Request
	connected: false
	buffer: ""
	response_offset: 0
	request: null
	processing: false
	connection_started_at: null
	last_data_received_at: null
	timeout_timer: null
	last_event_times: []
	opera_interval: null
	delay: 300
	stopped: false
	
	constructor: (account) ->
		super(account)
		@delay = settings.timings.mindelay
	
	toString: -> "StreamReq #{@account.user.screen_name}"
	
	clear_timeout: ->
		if @timeout_timer?
			window.clearTimeout(@timeout_timer)
			@timeout_timer = null
	
	set_timeout: (delay) ->
		@clear_timeout()
		@timeout_timer = window.setTimeout(@timeout, delay)
		Application.log(this, "set_timeout", "Delay: #{delay}")
	
	stop_request: ->
		@stopped = true
		@request.abort() if @request?
	
	restart: ->
		@request.abort() if @request?
	
	start_request: ->
		@stop_request()
		@stopped = false
		@account.set_status("Connecting to stream...", "orange")
		Application.log(this, "start_request", "Delay: #{@delay}")
		@last_event_times = []
		@set_timeout(settings.timeout_maximum_delay*1000)
		@processing = false
		@buffer = ""
		@response_offset = 0
		@connected = false
		@connection_started_at = new Date()
		data = @account.sign_request("https://userstream.twitter.com/2/user.json", "GET", {delimited: "length", include_entities: "1", include_rts: "1"})
		url = "user_proxy?#{data}"
		@request = new XMLHttpRequest();
		@request.open("GET", url, true);
		@request.onreadystatechange = =>
			@last_data_received_at = new Date()
			switch @request.readyState
				when 3
					@account.set_status("Connected.", "green") unless @connected
					@connected = true
				when 4
					@account.set_status("Disconnected", "red")
					@connected = false
					# Delay auf Minimum zurücksetzen, wenn die Verbindung länger als 60 Sekunden stand.
					@delay = settings.timings.mindelay if (new Date()).getTime() - @connection_started_at.getTime() > 60000
					@account.add_status_html("Disconnect.<br>Grund: #{@request.statusText}<br>Delay: #{@delay} Sekunden") unless @stopped
					Application.log(@, "onreadystatechange", "Disconnect. Delay jetzt: #{@delay}")
					window.setTimeout(@account.fill_list, @delay*1000) unless @stopped
					@delay = @delay * 2
					@stopped = false
			@buffer += @request.responseText.substr(@response_offset)
			@response_offset = @request.responseText.length
			@process_buffer()
		
		@request.send(null)
		window.clearInterval(@opera_interval) if @opera_interval?
		@opera_interval = window.setInterval(@request.onreadystatechange, 5000) if window.opera
		
	timeout: =>
		Application.log(this, "Timeout", "Timeout reached.")
		@account.add_status_html("Timeout vermutet.")
		@stop_request()
		@account.fill_list()
	
	process_buffer: ->
		return if @processing
		@processing = true
		regex = /^[\r\n]*([0-9]+)\r\n([\s\S]+)$/;
		while res=@buffer.match(regex)
			len = parseInt(res[1])
			break if res[2].length<len
			parseable_text = res[2].substr(0, len)
			@buffer = res[2].substr(len)
			try @account.parse_data(parseable_text)
			
			@last_event_times.unshift(new Date())
			@last_event_times.pop() if @last_event_times.length>(settings.timeout_detect_tweet_count+1)
			if @last_event_times.length >= 2
				average_tweet_delay = (@last_event_times[0]-@last_event_times[@last_event_times.length-1])/(@last_event_times.length-1)
				targeted_delay = average_tweet_delay * settings.timeout_detect_factor
				targeted_delay = settings.timeout_minimum_delay*1000 if settings.timeout_minimum_delay*1000 > targeted_delay
				targeted_delay = settings.timeout_maximum_delay*1000 if settings.timeout_maximum_delay*1000 < targeted_delay
				@set_timeout(@last_event_times[0].getTime()+targeted_delay-(new Date()).getTime())
			else
				@set_timeout(settings.timeout_maximum_delay*1000)
				
		@processing = false;
	