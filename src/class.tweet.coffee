class Tweet extends TwitterMessage
	# static variables
	@last: null
	
	mentions: []
	account: null
	thumbs: []
	id: null
	permalink: ""
	
	constructor: (data, @account) ->
		@data = data
		@id = data.id_str
		@fill_user_variables()
		@save_as_last_message()
		@permalink = "https://twitter.com/#{@sender.screen_name}/status/#{@id}"
		@account.tweets[@id] = this
		@text = if data.retweeted_status? then data.retweeted_status.text else data.text
		@entities = if data.retweeted_status? then data.retweeted_status.entities else data.entities
		@linkify_text()
		@thumbs = [] # Keine Ahnung, warum man das hier braucht... Lässt man es weg. sammeln sich die Thumbnails an.
		@get_thumbnails()
		@date = new Date(@data.created_at)
	
	fill_user_variables: -> 
		if @data.retweeted_status?
			@sender = new User(@data.retweeted_status.user)
			@retweeted_by = new User(@data.user)
		else
			@sender = new User(@data.user)
	
	save_as_last_message: -> Tweet.last = this
	get_date: -> @date
	div_id: -> "#tweet_#{@id}"
	get_html: ->
		"<div id='#{@id}' class='#{@get_classes().join(" ")}' data-tweet-id='#{@id}' data-account-id='#{@account.id}'>" +
		@get_single_thumb_html() +
		@sender.get_avatar_html() +
		@sender.get_link_html() +
		"<span class='text'>#{@text}</span>" +
		@get_multi_thumb_html() +
		@get_permanent_info_html() +
		@get_overlay_html() +
		"<div style='clear: both;'></div>" +
		"</div>"
		
	get_permanent_info_html: ->
		@get_retweet_html() +
		@get_place_html()
	
	get_overlay_html: -> 
		"<div class='overlay'>" +
		@get_temporary_info_html() +
		@get_buttons_html() +
		"</div>"
	
	get_temporary_info_html: ->
		"<div class='info'>" +
		"<a href='#{@permalink}' target='_blank'>#{@date.format_nice()}</a> #{@get_reply_to_info_html()} #{@get_source_html()}" + 
		"</div>"
			
	get_buttons_html: ->
		"<a href='#' onClick='return Tweet.hooks.reply(this);'><img src='icons/comments.png' title='Reply' /></a>" +
		"<a href='#' onClick='return Tweet.hooks.retweet(this);'><img src='icons/arrow_rotate_clockwise.png' title='Retweet' /></a>" +
		"<a href='#' onClick='return Tweet.hooks.quote(this);'><img src='icons/tag.png' title='Quote' /></a>" +
		"<a href='#{@permalink}' target='_blank'><img src='icons/link.png' title='Permalink' /></a>" +
		(if @data.coordinates? then "<a href='http://maps.google.com/?q=#{@data.coordinates.coordinates[1]},#{@data.coordinates.coordinates[0]}' target='_blank'><img src='icons/world.png' title='Geotag' /></a>" else "") +
		(if @data.coordinates? then "<a href='http://maps.google.com/?q=http%3A%2F%2Fapi.twitter.com%2F1%2Fstatuses%2Fuser_timeline%2F#{@sender.screen_name}.atom%3Fcount%3D250' target='_blank'><img src='icons/world_add.png' title='All Geotags' /></a>" else "") +
		(if @account.screen_name==@sender.screen_name then "<a href='#' onClick='return Tweet.hooks.delete(this);'><img src='icons/cross.png' title='Delete' /></a>" else "") +
		(if @account.screen_name!=@sender.screen_name then "<a href='#' onClick='return Tweet.hooks.report_as_spam(this);'><img src='icons/exclamation.png' title='Block and report as spam' /></a>" else "")
	
	get_single_thumb_html: ->
		return "" unless @thumbs.length==1
		return @thumbs[0].get_single_thumb_html()
	
	get_multi_thumb_html: ->
		return "" unless @thumbs.length>1
		html = "<div class='media'>"
		html += thumb.get_multi_thumb_html() for thumb in @thumbs
		html += "</div>"
		return html
	
	get_source_html: ->
		return "" unless @data.source?
		obj = $(@data.source)
		return "from <a href='#{obj.attr('href')}' target='_blank'>#{obj.html()}</a>" if obj.attr('href')
		return "from #{@data.source}"
		
	get_retweet_html: -> 
		return "" unless @retweeted_by?
		"<div class='retweet_info'>Retweeted by <a href='#{@retweeted_by.permalink}' target='_blank'>#{@retweeted_by.screen_name}</a></div>"
	
	get_place_html: ->
		return "" unless @data.place?
		"<div class='place'>from <a href='http://twitter.com/#!/places/#{@data.place.id}' target='_blank'>#{@data.place.full_name}</a></div>"
	
	get_reply_to_info_html: ->
		return "" unless @data.in_reply_to_status_id?
		"<a href='#' onClick='return Tweet.hooks.show_replies(this);'>in reply to...</a> "
	
	linkify_text: ->
		@mentions = [] # hack to prevent semi-static array mentions from filling up
		if @entities?
			all_entities = []
			for entity_type, entities of @entities
				for entity in entities
					entity.type=entity_type
					all_entities.push(entity)
			all_entities = all_entities.sort((a, b) -> a.indices[0] - b.indices[0]).reverse()
			for entity in all_entities
				switch entity.type
					when "user_mentions"
						@mentions.push entity.screen_name
						@replace_entity(entity, "<a href='https://twitter.com/#{entity.screen_name}' target='_blank'>@#{entity.screen_name}</a>")
					when "urls", "media"
						if entity.expanded_url?
							@replace_entity(entity, "<a href='#{entity.expanded_url}' class='external' target='_blank'>#{entity.display_url}</a>")
						else
							@replace_entity(entity, "<a href='#{entity.url}' class='external' target='_blank'>#{entity.url}</a>")
					when "hashtags"
						@replace_entity(entity, "<a href='https://twitter.com/search?q=##{entity.text}' target='_blank'>##{entity.text}</a>")
						Application.add_to_autocomplete("##{entity.text}")
		@text = @text.trim().replace(/\n/g, "<br />")
	
	replace_entity: (entity_object, text) -> @text = @text.slice(0, entity_object.indices[0]) + text + @text.slice(entity_object.indices[1])
	
	get_classes: ->
		classes = [
			"tweet"
			"by_#{@data.user.screen_name}"
			"new" if @account.is_unread_tweet(@id)
			"mentions_this_user" if @account.screen_name in @mentions
			"by_this_user" if @account.screen_name == @sender.screen_name
		]
		classes.push("mentions_#{mention}") for mention in @mentions
		classes
	
	retweet: ->
		return unless confirm("Wirklich retweeten?")
		@account.twitter_request("statuses/retweet/#{@id}.json", {success_string: "Retweet erfolgreich"})
	
	quote: ->
		$('#text').val("RT @#{@sender.screen_name}: #{@text}").focus()
		Application.reply_to(this)
	
	delete: ->
		return unless confirm("Wirklich diesen Tweet löschen?")
		@account.twitter_request("statuses/destroy/#{@id}.json", {success_string: "Tweet gelöscht", success: -> $(@div_id()).remove()})
	
	report_as_spam: -> @sender.report_as_spam(@account)
	
	reply: ->
		Application.set_dm_recipient_name(null)
		$('#text').val('').focus()
		Application.reply_to(this)
		sender = if @sender.screen_name!=@account.screen_name then "@#{@sender.screen_name} " else ""
		mentions = ("@#{mention} " for mention in @mentions.reverse() when mention!=@sender.screen_name && mention!=@account.screen_name).join("")
		$('#text').val("#{sender}#{mentions}")
		$('#text')[0].selectionStart = sender.length
		$('#text')[0].selectionEnd = sender.length + mentions.length
		$('#text').focus()
	
	get_thumbnails: ->
		return unless @data.entities?
		if @data.entities.media?
			for media in @data.entities.media
				@thumbs.push(new Thumbnail("#{media.media_url_https}:thumb", media.expanded_url))
		if @data.entities.urls?
			for entity in @data.entities.urls
				url = entity.expanded_url ? entity.url
				@thumbs.push(new Thumbnail("http://img.youtube.com/#{res[1]}/1.jpg", url)) if (res=url.match(/(?:http:\/\/(?:www\.)youtube.com\/.*v=|http:\/\/youtu.be\/)([0-9a-zA-Z_]+)/)) 
				@thumbs.push(new Thumbnail("http://twitpic.com/show/mini/#{res[1]}", url)) if (res=url.match(/twitpic.com\/([0-9a-zA-Z]+)/)) 
				@thumbs.push(new Thumbnail("http://yfrog.com/#{res[1]}.th.jpg", url)) if (res=url.match(/yfrog.com\/([a-zA-Z0-9]+)/)) 
				@thumbs.push(new Thumbnail("http://api.plixi.com/api/tpapi.svc/imagefromurl?url=#{url}&size=thumbnail", url)) if (res=url.match(/lockerz.com\/s\/[0-9]+/)) 
				@thumbs.push(new Thumbnail("http://moby.to/#{res[1]}:square", url)) if (res=url.match(/moby\.to\/([a-zA-Z0-9]+)/)) 
				@thumbs.push(new Thumbnail("http://ragefac.es/#{res[1]}/i", url)) if (res=url.match(/ragefac\.es\/(?:mobile\/)?([0-9]+)/))
				@thumbs.push(new Thumbnail("http://lauerfac.es/#{res[1]}/thumb", url)) if (res=url.match(/lauerfac\.es\/([0-9]+)/)) 
				@thumbs.push(new Thumbnail("http://ponyfac.es/#{res[1]}/thumb", url)) if (res=url.match(/ponyfac\.es\/([0-9]+)/))
	
	show_replies: ->
		html = ""
		tweet = this
		while true
			html += tweet.get_html()
			break unless tweet.data.in_reply_to_status_id_str?
			new_id = tweet.data.in_reply_to_status_id_str
			tweet = @account.tweets[new_id]
			unless tweet?
				html += '<div id="info_spinner"><img src="icons/spinner_big.gif" /></div>'
				@fetch_reply(new_id)
				break
		Application.infoarea.show("Replies", html)
	
	fetch_reply: (id) ->
		@account.twitter_request('statuses/show.json', {
			parameters: {id: id, include_entities: true}
			silent: true
			method: "GET"
			success: (foo, data) =>
				tweet = new Tweet(data, @account)
				$('#info_spinner').before(tweet.get_html())
				if Application.infoarea.visible && tweet.data.in_reply_to_status_id_str
					@fetch_reply(tweet.data.in_reply_to_status_id_str)
				else
					$('#info_spinner').remove()
		})
	
	@hooks: {
		get_tweet: (element) -> 
			tweet_div = $(element).parents('.tweet')
			Application.accounts[tweet_div.attr('data-account-id')].get_tweet(tweet_div.attr('data-tweet-id'))
		
		reply:          (elm) -> @get_tweet(elm).reply(); return false
		retweet:        (elm) -> @get_tweet(elm).retweet(); return false
		quote:          (elm) -> @get_tweet(elm).quote(); return false
		delete:         (elm) -> @get_tweet(elm).delete(); return false
		report_as_spam: (elm) -> @get_tweet(elm).report_as_spam(); return false
		show_replies:   (elm) -> @get_tweet(elm).show_replies(); return false
		
		# called by the tweet button
		send: ->
			# event is a global variable. preventDefault() prevents the form from being submitted after this function returned
			event.preventDefault() if event?
			parameters = {
				status: $('#text').val().trim()
				wrap_links: true
			}
			if settings.places.length > 0 && (placeindex=document.tweet_form.place.value-1)>=0
				place = settings.places[placeindex]
				parameters.lat = place.lat + (((Math.random()*300)-15)*0.000001)
				parameters.lon = place.lon + (((Math.random()*300)-15)*0.000001)
				parameters.place_id = place.place_id if place.place_id?
				parameters.display_coordinates = true
			parameters.in_reply_to_status_id = Application.reply_to().id if Application.reply_to()?
			
			if $('#file')[0].files[0]
				data = Application.current_account.sign_request("https://upload.twitter.com/1/statuses/update_with_media.json", "POST", null)
				url = "proxy/upload/statuses/update_with_media.json?#{data}"
				content_type = false
				data = new FormData()
				data.append("media[]", $('#file')[0].files[0])
				data.append(key, value) for key, value of parameters
			else
				data = Application.current_account.sign_request("https://api.twitter.com/1/statuses/update.json", "POST", parameters)
				url = "proxy/api/statuses/update.json"
				content_type = "application/x-www-form-urlencoded"
			$('#form').fadeTo(500, 0);
			
			$.ajax({
				url: url
				data: data
				processData: false
				contentType: content_type
				async: true
				dataType: "json"
				type: "POST"
				success: (data) ->
					if data.text
						html = "
							Tweet-ID: #{data.id_str}<br />
							Mein Tweet Nummer: #{data.user.statuses_count}<br />
							Follower: #{data.user.followers_count}<br />
							Friends: #{data.user.friends_count}<br />"
						$('#text').val('')
						Application.reply_to(null)
						Hooks.toggle_file(false)
						$('#success_info').html(html)
						$('#success').fadeIn(500).delay(2000).fadeOut(500, -> $('#form').fadeTo(500, 1))
					else
						$('#failure_info').html(data.error);
						$('#failure').fadeIn(500).delay(2000).fadeOut(500, -> $('#form').fadeTo(500, 1))
				error: (req) ->
					info = "Error #{req.status} (#{req.statusText})"
					try additional = $.parseJSON(req.responseText)
					info += "<br /><strong>#{additional.error}</strong>" if additional?.error?
					$('#failure_info').html(info)
					$('#failure').fadeIn(500).delay(2000).fadeOut(500, -> $('#form').fadeTo(500, 1))
			})
			
			return false
	}
