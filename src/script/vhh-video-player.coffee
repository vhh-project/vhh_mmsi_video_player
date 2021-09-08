window.VhhVideoPlayer = class VhhVideoPlayer
  # Under this rate use "fake" playback rate by using timeout events
  MIN_PLAYBACK_RATE: 0.1

  # Time options for video in general and film
  TIME_OPTIONS: [ 'frame', 'float', 'smpte', 'simple' ]
  TIME_OPTIONS_FILM: [ 'meter', 'inches' ]

  # How long are the controls faded in when no mouse is moved
  FULLSCREEN_FADE_TIMEOUT: 1000

  # Initial audio volume
  INITIAL_AUDIO_VOLUME: 0.75

  volumeBeforeMuted: 0.75

  # Used for multiple instances of the player on the same document
  @idCounter: 1

  # Simple translations, can be overridden on creation
  translations:
    frame: 'Frame'
    float: 'Float'
    smpte: 'SMPTE'
    simple: 'Time'
    meter: 'Meter'
    inches: 'Inches'
    fps: 'fps'
    default: 'default'
    quality: 'Quality'
    video_button_prev_shot: 'Jump to previous shot [⇧←]'
    video_button_prev_frame: 'Jump to previous frame [←]'
    video_button_play_reverse: 'Play Reverse / Pause [⇧ + SPACE]'
    video_button_play: 'Play / Pause [SPACE]'
    video_button_next_frame: 'Jump to next frame [→]'
    video_button_next_shot: 'Jump to next shot [⇧→]'
    video_button_fullscreen: 'Fullscreen'
    video_button_settings: 'Settings'
    audio_button: 'Mute / unmute audio'
    other_settings: 'Other Settings'
    mirror: 'Mirror Video'
    mirror_off: 'Mirror off'
    mirror_on: 'Mirror on'
    overscan: 'Overscan'
    overscan_on: 'Hide Maks'
    overscan_off: 'Show Mask'
    zoom: 'Zoom'
    zoom_on: 'Zoom on'
    zoom_off: 'Zoom off'

  # Hotkeys that work on document level, do not interfer with form inputs
  hotkeys: [
    { key: 32, func: 'clickPlay' }                          # Arrow left
    { key: 32, shiftKey: true, func: 'clickPlayBackward' }  # Arrow left
    { key: 37, func: 'clickPrevFrame' }                      # Arrow left
    { key: 37, shiftKey: true, func: 'seekPrevShot' }       # Arrow left & shift
    { key: 39, func: 'clickNextFrame' }                      # Arrow right
    { key: 39, shiftKey: true, func: 'seekNextShot' }       # Arrow left & shift
    { key: '+', func: 'nextFrameRate' }
    { key: '-', func: 'prevFrameRate' }
    { key: '0', func: 'setDefaultFrameRate' }
    { key: '1', func: 'setFrameRate1' }
    { key: '2', func: 'setFrameRate2' }
    { key: '6', func: 'setFrameRate6' }
    { key: 'j', func: 'focusTimeCounter' }
    { key: 'J', shiftKey: true, func: 'focusTimeCounterAndSelectFrames' }
  ]

  # Used for playback rates below MIN_PLAYBACK_RATE
  playingByInterval: false
  playbackIntervalId: null

  # Indicates if playing
  playing: false
  playBackward: false

  constructor: (data) ->
    # Create a unique ID for the player DOM element
    @id = 'vhh-video-player-' + VhhVideoPlayer.idCounter
    VhhVideoPlayer.idCounter++

    # Remember the container in order to attach the player to it
    @$container = $(data.container)

    # Mediator that allows communication for between video and other UI components
    @mediator = data.mediator
    @mediator?.videoPlayer = @

    # (Optional) When true, the player adjusts the height so the video fits perfectly
    @adjustHeight = data.adjustHeight == true

    unless @adjustHeight
      @adjustHeightToContainer = data.adjustHeightToContainer == true

    unless @adjustHeightToContainer
      # (Optional) a target height for the video
      @height = data.height or 300

    # (Optional) Translations can be overridden
    if data.translations?
      for key, value of data.translations
        @translations[key] = value

    # (Optional) Posterframe is shown before video plays
    @posterframe = data.video.posterframe

    # Create video object with data about the video (source, hls, ...)
    @video = new VhhVideoPlayer.Video(data.video)

    # Start with default frames per second (fps)
    @currentFps = @video.fps

    # (Optional) When true, more options for the film counter are available
    @isFilm = data.video.isFilm == true

    if @isFilm
      @timeOptions = @TIME_OPTIONS.concat(@TIME_OPTIONS_FILM)

    else
      @timeOptions = @TIME_OPTIONS

    # Counter type is frame by default
    @currentCounterType = 'frame'

    # Optionally calculate frame offset when total number of frames is given
    @calculateFrameOffset = data.calculateFrameOffset or false

    # Optionally auto-detect the length of the first frame in order to get an offset
    @detectFirstFrame = data.detectFirstFrame or false

    @canMirror = if data.canMirror? then data.canMirror else true

    @showMirror = false

    if data.video.mask?
      @canShowMask = if data.canShowMask? then data.canShowMask else false
      @showMask = if data.showMask? then data.showMask == true else false
      @canShowZoom = if data.canShowZoom? then data.canShowZoom == true else false
      @showZoom = if data.showZoom? then (not @showMask) and data.showZoom == true else false

    else
      @canShowMask = false
      @showMask = false
      @canShowZoom = false
      @showZoom = false

    # Handle hotkeys
    $(document).on('keydown', @handleHotkeys)

    # Finally, render the player in the DOM
    @render()

  # Renders the UI, attaches the video, sets frequently used DOM elements
  render: ->
    # Prepare attributes for the <video> tag
    videoAttributes = []
    videoAttributes.push(" poster=\"#{@posterframe}\"") if @posterframe?

    # Render the Handlebars template
    html = @mainTemplate
      id: @id
      videoAttributes: videoAttributes.join('')
      source: @video.source
      canShowMask: @canShowMask
      showMask: @showMask
      mask: @video.mask
      translations: @translations
      fpsOptions: @getFpsOptions()
      counterOptions: @getVideoCounterTypeOptions()
      settingsOptions: @getSettingsOptions()
      volume: @INITIAL_AUDIO_VOLUME * 100
    
    @$container.html(html)

    # Remember the most used UI DOM elements
    @$el = $("##{@id}")
    @$video = @$el.find('video')
    @$videoMask = @$video.parent()
    @$overscanMask = @$el.find('.vhh-video-mask')
    @$controls = @$el.find('.vhh-video-player-controls')
    @$timeline = @$controls.find('.vhh-video-player-timeline')
    @$timelineBar = @$timeline.find('.vhh-video-player-timeline-bar')
    @$timelineGrip = @$timelineBar.find('.vhh-video-player-timeline-grip')
    @$playButton = @$controls.find('.vhh-video-player-button-play')
    @$playButtonBackward = @$controls.find('.vhh-video-player-button-play-backward')
    @$prevFrameButton = @$el.find('.vhh-video-player-button-prev-frame')
    @$nextFrameButton = @$el.find('.vhh-video-player-button-next-frame')
    @$prevShotButton = @$el.find('.vhh-video-player-button-prev-shot')
    @$nextShotButton = @$el.find('.vhh-video-player-button-next-shot')
    @$inputCounter = @$el.find('.vhh-video-player-input-counter')
    @$audioVolume = @$el.find('.vhh-video-player-audio')
    @$audioVolumeBar = @$audioVolume.find('.vhh-video-player-audio-bar')
    @$audioVolumeGrip = @$audioVolumeBar.find('.vhh-video-player-audio-grip')
    @$audioVolumeButton = @$audioVolume.find('button')
    @$fullscreenButton = @$el.find('.vhh-video-player-button-fullscreen')

    # Setting a initial audio volume
    @$video[0].volume = @INITIAL_AUDIO_VOLUME
    @setAudioVolume()

    if @adjustHeightToContainer == true
      @$el.addClass('adjust-height-to-container')

    else if @height?
      @$videoMask.parent().css(height: "#{@height}px")

    $(window).on('resize', @onWindowResize) 

    # Check which method should be used for playing the video
    if @video.hls? and Hls.isSupported()
      @hls = new Hls
        debug: false
        enableWorker: true

      currentHlsItem = @video.getHlsByResolution('auto')

      @hls.loadSource(currentHlsItem.src)
      @hls.attachMedia(@$video[0])
      
      @attachVideoEvents()
      @attachHlsEvents()

    else if @video.source?
      @attachVideoEvents()

    else
      console.warn 'Either no HLS support or no source available'    

  # Attaches UI events on DOM elements
  attachEvents: ->
    # Make shure all dropdowns are closed when clicked somewhere outside
    $(document).on('click', @clickDocument)

    # Open and close dropdown menus
    @$el.find('.vhh-video-player-menu > button').on('click', @clickDropdown)

    # Handle clicks on a dropdown list item
    @$el.find('button.vhh-video-player-menu-list-item').on('click', @clickDropDownItem)

    @$playButtonBig = @$el.find('.vhh-video-player-big-button-play')
    @$playButtonBig.on('click', @clickPlay)

    @$playButton.on('click', @clickPlay)
    @$videoMask.parent().on('click', @clickVideo)
    @$playButtonBackward.on('click', @clickPlayBackward)
    @$prevFrameButton.on('click', @clickPrevFrame)
    @$nextFrameButton.on('click', @clickNextFrame)
    @$prevShotButton.on('click', @seekPrevShot)
    @$nextShotButton.on('click', @seekNextShot)
    @$inputCounter.on('keydown', @keydownVideoInputCounter)
    @$inputCounter.on('blur', @blurVideoInputCounter)

    @$timelineGrip.on('mousedown', @mousedownTimelineGrip)
    @$timeline.on('click', @clickTimeline)

    @$audioVolumeButton.on('click', @clickVolumeButton)
    @$audioVolumeBar.on('click', @clickAudioVolumeBar)
    @$audioVolumeGrip.on('mousedown', @mousedownAudioVolumeGrip)

    @$el.on('fullscreenchange', @onFullscreenchange)
    @$el.on('webkitfullscreenchange', @onFullscreenchange)
    @$fullscreenButton.on('click', @clickFullscreen)

  attachFullscreenHandlers: ->
    @$video.on('mousemove', @mousemoveFullscreen)
    @$overscanMask.on('mousemove', @mousemoveFullscreen)
    @$controls.on('mousemove', @mousemoveFullscreen)

  # Attaches events on video
  attachVideoEvents: ->
    @$video.on('loadeddata', @onLoadedData)
    @$video.on('play', @onPlay)
    @$video.on('pause', @onPause)
    @$video.on('timeupdate', @onTimeupdate)
    @$video.on('seeked', @onSeeked)

  attachHlsEvents: ->
    @hls.on(Hls.Events.LEVEL_SWITCHED, @onHlsLevelSwitched)

  # Remove handlers related to fullscreen
  detachFullscreenHandlers: ->
    @$video.off('mousemove')
    @$overscanMask.off('mousemove', @mousemoveFullscreen)
    @$controls.off('mousemove', @mousemoveFullscreen)

    if @fullscreenFadeTimer?
      window.clearTimeout(@fullscreenFadeTimer)
      delete @fullscreenFadeTimer

    @$controls.stop()

  detachHlsEvents: ->
    @hls.off('Hls.Events.LEVEL_SWITCHED')

  # Detaches events from video
  detachVideoEvents: ->
    @$video.off('loadeddata')
    @$video.off('play')
    @$video.off('pause')
    @$video.off('timeupdate')

  # This method should be called to remove all handlers before destroying the DOM
  remove: ->
    # Remove hotkey handler
    $(document).off 'keydown', @handleHotkeys

    # Remove mouse handlers just to be sure
    @removeTimelineHandlers()
    @mouseupAudioVolumeGrip()

    @detachVideoEvents()
    @detachHlsEvents() if @hls?

    $(window).off('resize', @onWindowResize)

    # Remove UI handlers
    @$el.find('.vhh-video-player-menu > button').off('click')
    @$el.find('.vhh-video-player-menu-list-item').off('click')

    @removePlayButtonBig()

    @$playButton.off('click')
    @$video.off('click')
    @$playButtonBackward.off('click')
    @$prevFrameButton.off('click')
    @$nextFrameButton.off('click')
    @$prevShotButton.off('click')
    @$nextShotButton.off('click')
    @$inputCounter.off('keydown')
    @$inputCounter.off('blur')

    @$timelineGrip.off('mousedown')
    @$timeline.off('click')

    @$audioVolumeButton.off('click')
    @$audioVolumeBar.off('click')
    @$audioVolumeGrip.off('mousedown')

    @$el.off('fullscreenchange')
    @$fullscreenButton.off('click')
    @detachFullscreenHandlers()

    # Finally remove the player from the DOM
    @$el.remove()

    # Just to be sure, clear the frame interval
    @clearFrameInterval()

    # Destroy HLS streaming
    @hls?.destroy()

  # Remove handlers from timeline
  removeTimelineHandlers: ->
    $(window)
      .off('mousemove', @mousemoveTimelineGrip)
      .off('mouseup', @mouseupTimelineGrip)
  
  #############################################################################
  # General UI Handlers #######################################################
  #############################################################################

  # When the user has clicked outside the dropdowns, we want to close them when open
  clickDocument: =>
    @blurControlFullscreen()
    @closeMenus()

  # When clicking on a dropdown, we want to open the list
  clickDropdown: (event) =>
    event.stopPropagation()

    $menu = $(event.currentTarget).parent()
    @closeMenus($menu[0])

    if $menu.hasClass('open')
      $menu.removeClass('open')
      @blurControlFullscreen()

    else
      $menu.addClass('open')
      @focusControlFullscreen()
      

  # Handles clicks on a dropdown item
  clickDropDownItem: (event) =>
    $node = $(event.currentTarget)
    $menu = $node.closest('.vhh-video-player-menu')
    
    key = $node.data('key')
    value = $node.data('value')

    $node.parent().find("[data-key=\"#{key}\"]").removeClass('active')
    $node.addClass('active')

    if $menu.data('change-button')
      $menu.find('> button > span').text($node.find('.text').text())

    @blurControlFullscreen()

    @clickMenuItem(key, value)

  # Handles all hotkeys given in @hotkeys
  handleHotkeys: (event) =>
    return if event.target.nodeName in ['INPUT', 'TEXTAREA'] or event.metaKey == true or event.ctrlKey == true or event.altKey == true
    
    for hotkey in @hotkeys
      found = false
      
      shiftKey = hotkey.shiftKey == true

      unless shiftKey != event.shiftKey
        if typeof hotkey.key == 'string'
          found = hotkey.key == event.key

        else if typeof hotkey.key == 'number'
          found = hotkey.key == event.keyCode

        if found == true
          event.stopPropagation()
          event.preventDefault()

          @[hotkey.func]?()

  #############################################################################
  # UI Handlers ###############################################################
  #############################################################################

  # When counter input has been blurred, show current time
  blurVideoInputCounter: (event) =>
    @blurControlFullscreen()
    @updateInputCounter(event.currentTarget)

  # Set the audio volume immediately
  clickAudioVolumeBar: (event) =>
    offsetX = event.pageX - @$audioVolumeBar.offset().left
    @setAudioVolume(offsetX / @$audioVolumeBar.innerWidth())

  # Try to go fullscreen via browser native method requestFullscreen
  clickFullscreen: =>
    if document.fullscreenEnabled
      if document.fullscreenElement != null
        document.exitFullscreen()

      else
        @$el[0].requestFullscreen()

    else if document.webkitFullscreenEnabled
      if document.webkitFullscreenElement != null
        document.webkitExitFullscreen()

      else
        @$el[0].webkitRequestFullscreen()

    else
      console.warn 'Fullscreen API not available in this browser'
    

  # Called when a dropdown menu item has been clicked
  clickMenuItem: (key, value) ->
    switch key
      when 'fps'
        @selectFps(value)

      when 'counter-option'
        @selectCounterType(value)

      when 'hls'
        @selectHlsByResolution(value)

      when 'mirror'
        @changeMirroring(value)

      when 'overscan'
        @changeOverscan(value)

      when 'zoom'
        @changeZoom(value)

  # Click on jump to next frame button
  clickNextFrame: =>
    @playing = false
    @playBackward = false
    @togglePlaying()

    @seekNextFrame()
  
  # Click on play buttons
  clickPlay: (event) =>
    event?.stopPropagation()

    unless @playBackward == true and @playing == true 
      @playing = not @playing

    @playBackward = false

    @togglePlaying()

  # Click on play reverse button
  clickPlayBackward: =>
    unless @playBackward == false and @playing == true 
      @playing = not @playing

    @playBackward = true

    @togglePlaying()

  # Click on jump to previous frame button
  clickPrevFrame: =>
    @playing = false
    @playBackward = false
    @togglePlaying()

    @seekPrevFrame()
  
  # Click in timeline - jump in video
  clickTimeline: (event) =>
    offsetX = event.pageX - @$timeline.offset().left
    @seekRelative(offsetX / @$timeline.innerWidth())

  # Click on <video>
  clickVideo: (event) =>
    event?.stopPropagation()

    @closeMenus()

    if @playing
      @playing = false
      @playBackward = false
      @togglePlaying()

    else
      @clickPlay()

  # Click on the volume button toggles mute
  clickVolumeButton: =>
    if @$video[0].volume > 0
      @volumeBeforeMuted = @$video[0].volume
      newVolume = 0

    else
      newVolume = @volumeBeforeMuted or @INITIAL_AUDIO_VOLUME

    @setAudioVolume(newVolume)

  # Select whole text in counter input on focus for faster jumping
  focusTimeCounter: ->
    @focusControlFullscreen()
    @$el.find('.vhh-video-player-input-counter').focus().select()

  # Select frames for time counter and select whole text for faster jumping
  focusTimeCounterAndSelectFrames: ->
    @focusControlFullscreen()
    @$el.find('.select-vhh-video-player-counter-type button[data-value="frame"]').click()
    @focusTimeCounter()

  # Fetches enter and ESC in the counter input
  keydownVideoInputCounter: (event) =>
    # Enter pressed - jump to frame, timecode, etc.
    if event.keyCode == 13
      @seek(event.currentTarget.value, @currentCounterType)
      event.currentTarget.blur()

    # ESC pressed - cancel
    else if event.keyCode == 27
      event.currentTarget.blur()

  # Start timeline navigation on mousedown
  mousedownTimelineGrip: =>
    @focusControlFullscreen()

    @$timelineGrip.addClass('dragging')
    @$timelineBar.addClass('no-update')

    $(window)
      .on('mousemove', @mousemoveTimelineGrip)
      .on('mouseup', @mouseupTimelineGrip)

  # When moving mouse while timeline grip is clicked, navigate in time
  mousemoveTimelineGrip: (event) =>
    @clickTimeline(event)
  
  # End timeline navigation
  mouseupTimelineGrip: =>
    @$timelineGrip.removeClass('dragging')
    @$timelineBar.removeClass('no-update')

    @clickTimeline(event)
    @blurControlFullscreen()
    @removeTimelineHandlers()

  # Start adjusting the volume
  mousedownAudioVolumeGrip: =>
    @focusControlFullscreen()

    $(window)
      .on('mousemove', @mousemoveAudioVolumeGrip)
      .on('mouseup', @mouseupAudioVolumeGrip)

  # Adjust volume
  mousemoveAudioVolumeGrip: (event) =>
    @clickAudioVolumeBar(event)

  # In fullscreen mode, show controls when mouse is moving
  mousemoveFullscreen: =>
    return unless document.fullscreenElement or document.webkitFullscreenElement

    if @fullscreenIn == true
      @countFadeoutFullscreenControls()

    else
      @$controls.stop()

      @fullscreenIn = true

      @$controls.css
        display: 'block'

      @$controls.animate { opacity: 1 },
        complete: @countFadeoutFullscreenControls

  # End adjusting the volume
  mouseupAudioVolumeGrip: (event) =>
    if event?
      @clickAudioVolumeBar(event) 
      @blurControlFullscreen()

    $(window)
      .off('mousemove', @mousemoveAudioVolumeGrip)
      .off('mouseup', @mouseupAudioVolumeGrip)

  # A new counter type (frame, SMPTE, ...) has been selected
  selectCounterType: (value) ->
    @currentCounterType = value
    @updateInputCounter()

  # A new video resolution has been selected
  selectHlsByResolution: (value) ->
    hls = @video.getHlsByResolution(value)
    index = @getHlsIndexBySrc(hls.src)
    @hls.currentLevel = index

  # New FPS have been selected
  selectFps: (value) ->
    @currentFps = parseInt(value)
    @updatePlaybackRate()

  # Change mirroring of video
  changeMirroring: (value) ->
    @showMirror = value == 'on'
    @$videoMask.parent().toggleClass('vhh-video-player-mirrored', @showMirror)

  # Change overscan of video
  changeOverscan: (value) ->
    $menu = @$el.find('.vhh-video-player-menu')
    $menu.find('[data-key="zoom"][data-value="off"]').addClass('active')
    $menu.find('[data-key="zoom"][data-value="on"]').removeClass('active')
    @$video.toggleClass('vhh-video-zoomed', false)
    
    @showZoom = false
    @showMask = value == 'off'
    @$overscanMask.toggleClass('vhh-video-mask-show', @showMask)

    @adjustVideoDimensions()

  # Change zoom of video
  changeZoom: (value) ->
    $menu = @$el.find('.vhh-video-player-menu')
    $menu.find('[data-key="overscan"][data-value="off"]').removeClass('active')
    $menu.find('[data-key="overscan"][data-value="on"]').addClass('active')
    @$overscanMask.toggleClass('vhh-video-mask-show', false)

    @showMask = false
    @showZoom = value == 'on'
    @$overscanMask.toggleClass('vhh-video-zoomed', @showZoom)

    @adjustVideoDimensions()

  #############################################################################
  # Video Handlers ############################################################
  #############################################################################

  # Fired when video switches to fullscreen mode and back
  onFullscreenchange: (event) =>
    if document.fullscreenElement or document.webkitFullscreenElement
      @$el.addClass('fullscreen')

      @$video.css
        height: ''

      @$controls.css
        opacity: 1
        display: 'block'

      @countFadeoutFullscreenControls()
      @attachFullscreenHandlers()

    else
      @$el.removeClass('fullscreen')
      
      @$controls.css
        'display': ''
        'opacity': 1

      @detachFullscreenHandlers()

    window.setTimeout(@adjustVideoDimensions, 100)

  onHlsLevelSwitched: (eventType, data) =>
    $text = @$el.find('.vhh-video-player-quality')
    hlsItem = @video.getHlsByUrl(@hls.levels[data.level].url[0])

    if hlsItem?
      $text.text(hlsItem.label)

    else 
      $text.text('')

  onWindowResize: =>
    return unless @$el.hasClass('fullscreen') or @adjustHeightToContainer
    @adjustVideoDimensions()

  # Fired when video has been loaded
  onLoadedData: =>
    @adjustVideoDimensions()
    @$controls.addClass('video-loaded')
    @attachEvents()

    if @calculateFrameOffset == true and @video.frames? and not isNaN(@video.frames)
      # (@video.frameLength * 0.2) is extra safe duration added in favor of MMSI-542
      @video.frameOffset = Math.max(0, @$video[0].duration - (@video.frames * @video.frameLength) + (@video.frameLength * 0.2))
      
      # Try not to let the offset get too big
      @video.frameOffset = Math.min(@video.frameOffset, @video.frameLength * 0.95)

      @video.lastFrameTime = @video.frameLength * (@video.frames - 1) + (@video.frameLength / 4) + @video.frameOffset

      # console.log '@$video[0].mozHasAudio:', @$video[0].mozHasAudio
      # console.log '@$video[0].webkitAudioDecodedByteCount:', @$video[0].webkitAudioDecodedByteCount
      # console.log '@$video[0].audioTracks:', @$video[0].audioTracks

      # console.log '@$video[0].duration:', @$video[0].duration
      # console.log 'frames:', @video.frames
      # console.log '@video.lastFrameTime:', @video.lastFrameTime
      # console.log '@video.frames * @video.frameLength:', @video.frames * @video.frameLength
      # console.log '@video.frameOffset:', @video.frameOffset
      # console.log 'fps / @video.frameLength:', @video.fps, @video.frameLength

    else if @detectFirstFrame == true
      @detectFirstFrameTimeLength = @video.frameLength / 10
      
      @firstFrameCanvas = document.createElement('canvas')
      @firstFrameCanvas.width = 10
      @firstFrameCanvas.height = 10
      @firstFrameContext = @firstFrameCanvas.getContext('2d')

      @$video[0].currentTime = @video.frameLength / 2

  # Fired when video seek is finished
  onSeeked: (event) =>
    if @detectFirstFrame == true
      @firstFrameContext.drawImage(@$video[0], 0, 0, 10, 10)
      pixel = @firstFrameContext.getImageData(1, 1, 1, 1).data;
      
      if pixel[0] >= 200 and pixel[1] > 200 and pixel[2] > 200 and pixel[3] > 200
        # console.log 'still first frame :/'
        @$video[0].currentTime += @detectFirstFrameTimeLength

      else
        delete @detectFirstFrame
        delete @detectFirstFrameTimeLength
        delete @firstFrameContext
        delete @firstFrameCanvas

        # console.log 'FOUND second frame :)', @$video[0].currentTime

        @video.frameOffset = Math.max(0, @$video[0].currentTime - @video.frameLength)
        @video.lastFrameTime = @video.frameLength * (@video.frames - 1) + (@video.frameLength / 4) + @video.frameOffset

        # console.log '@video.frameOffset:', @video.frameOffset

        @seek(1, 'frame')
      

  # Fired when video starts playing
  onPlay: =>
    @playing = true
    @toggleControls()

  # Fired when video is paused
  onPause: =>
    return if @playingByInterval == true
    
    @playing = false
    @toggleControls()

    # Hack to actually nail the current frame
    @seek(@$video[0].currentTime, ' ')
  
  # Fired when there is new information about the current video time
  onTimeupdate: =>
    @updateTimeline() unless @$timelineBar.hasClass('no-update')
    @updateInputCounter()

  #############################################################################
  # Custom and Helper Methods #################################################
  #############################################################################

  adjustVideoDimensions: =>
    $wrapper = @$videoMask.parent()
    $wrapper.css
      height: ''

    wrapperWidth = $wrapper.width()
    videoAspect = @$video[0].videoWidth / @$video[0].videoHeight
    adjustHeight = @adjustHeight == true and not @$el.hasClass('fullscreen')

    if @showZoom
      boxH = Math.max(0.1, 1 - @video.mask.left - @video.mask.right)
      boxV = Math.max(0.1, 1 - @video.mask.top - @video.mask.bottom)

      zoomH = 1 / boxH
      zoomV = 1 / boxV

      if adjustHeight
        wrapperHeight = wrapperWidth * zoomH / videoAspect * boxV
        $wrapper.css
          height: "#{wrapperHeight}px"

        if boxH < boxV
          videoLeft = ((zoomH - 1) / 2) - (@video.mask.left * zoomH)
          videoTop = ((1 - boxV) / boxV / 2) - (@video.mask.top / boxV)

          videoMaskCSS =
            width: "#{wrapperWidth}"
            height: "#{wrapperHeight}"
            left: 0
            top: 0

          @$video.css
            transform: "translate(#{videoLeft * 100}%, #{videoTop * 100}%) scale(#{zoomH}, #{zoomH})"

        else
          videoLeft = ((1 - boxH) / boxH / 2) - (@video.mask.left / boxH)
          videoTop = ((zoomV - 1) / 2) - (@video.mask.top * zoomV)

          videoMaskCSS =
            width: "#{wrapperWidth}"
            height: "#{wrapperHeight}"
            left: 0
            top: 0

          @$video.css
            transform: "translate(#{videoLeft * 100}%, #{videoTop * 100}%) scale(#{zoomV}, #{zoomV})"

      else
        if @adjustHeightToContainer or @$el.hasClass('fullscreen')
          wrapperHeight = $wrapper.height()

        else
          wrapperHeight = @height
          $wrapper.css
            height: "#{wrapperHeight}px"

        wrapperAspect = wrapperWidth / wrapperHeight
        zoomAspect = zoomV / zoomH * videoAspect

        if boxH < boxV
          videoLeft = ((zoomH - 1) / 2) - (@video.mask.left * zoomH)
          videoTop = ((1 - boxV) / boxV / 2) - (@video.mask.top / boxV)

          transform = "translate(#{videoLeft * 100}%, #{videoTop * 100}%) scale(#{zoomH}, #{zoomH})"

        else
          videoLeft = ((1 - boxH) / boxH / 2) - (@video.mask.left / boxH)
          videoTop = ((zoomV - 1) / 2) - (@video.mask.top * zoomV)

          transform = "translate(#{videoLeft * 100}%, #{videoTop * 100}%) scale(#{zoomV}, #{zoomV})"

        if wrapperAspect <= zoomAspect
          videoWidth = wrapperWidth
          videoHeight = wrapperWidth * zoomH / videoAspect * boxV

          videoMaskCSS =
            width: "#{videoWidth}px"
            height: "#{videoHeight}px"
            left: 0
            top: "#{(wrapperHeight - videoHeight) / 2}px"

          @$video.css
            transform: transform

        else
          videoWidth = wrapperHeight / zoomH * videoAspect / boxV
          videoHeight = wrapperHeight

          videoMaskCSS =
            width: "#{videoWidth}px"
            height: "#{videoHeight}px"
            left: "#{(wrapperWidth - videoWidth) / 2}px"
            top: 0
            
          @$video.css
            transform: transform

    # No Zoom - with or without mask
    else
      @$video.css
        transform: ''

      if adjustHeight
        wrapperHeight = wrapperWidth / videoAspect

        $wrapper.css
          height: "#{wrapperHeight}px"

        videoMaskCSS =
          width: "#{wrapperWidth}px"
          height: "#{wrapperHeight}px"
          left: 0
          top: 0

      else
        if @adjustHeightToContainer or @$el.hasClass('fullscreen')
          wrapperHeight = $wrapper.height()

        else
          wrapperHeight = @height
          $wrapper.css
            height: "#{wrapperHeight}px"
        
        wrapperAspect = wrapperWidth / wrapperHeight
      
        if wrapperAspect < videoAspect
          videoMaskCSS =
            width: "#{wrapperWidth}px"
            height: "#{wrapperWidth / videoAspect}px"
            left: 0
            top: "#{(wrapperHeight - (wrapperWidth / videoAspect)) / 2}px"

        else
          videoMaskCSS =
            width: "#{wrapperHeight * videoAspect}px"
            height: "#{wrapperHeight}px"
            left: "#{(wrapperWidth - (wrapperHeight * videoAspect)) / 2}px"
            top: 0

      @$overscanMask.css(videoMaskCSS)

    @$videoMask.css(videoMaskCSS)

  blurControlFullscreen: ->
    @controlFocused = false
    @countFadeoutFullscreenControls()

  # Remove the frame interval
  clearFrameInterval: ->
    if @playbackIntervalId?
      window.clearInterval(@playbackIntervalId)
      delete @playbackIntervalId

  closeMenus: (clickedMenu) ->
    $menus = @$el.find('.vhh-video-player-menu')

    if clickedMenu?
      $menus.each ->
        $(@).removeClass('open') if @ != clickedMenu

    else
      $menus.removeClass('open')      

  # Set timer in order to fade out controls after some time when in fullscreen mode
  countFadeoutFullscreenControls: =>
    if @fullscreenFadeTimer?
      window.clearTimeout(@fullscreenFadeTimer)

    return if @controlFocused == true or ((not document.fullscreenElement) and (not document.webkitFullscreenElement))

    @fullscreenFadeTimer = window.setTimeout(@fadeoutFullscreenControls, @FULLSCREEN_FADE_TIMEOUT)

  fadeoutFullscreenControls: =>
    delete @fullscreenFadeTimer
    @fullscreenIn = false

    @$controls.animate { opacity: 0 },
      complete: =>
        @$controls.css
          display: ''

  # Used when in fullscreen mode and a control (eg. input) is focused
  focusControlFullscreen: ->
    @controlFocused = true
    @mousemoveFullscreen()

  # Create options for the settings menu (video quality)
  getSettingsOptions: ->
    items = []

    if @video.hls? and Hls.isSupported()
      items.push
        type: 'custom'
        html: "<strong>#{@translations.quality}</strong><span class=\"vhh-video-player-quality\">720p</span>"

      for hlsItem in @video.hls
        items.push
          active: hlsItem.resolution == 'Auto'
          label: hlsItem.label
          key: 'hls'
          value: hlsItem.resolution

    if @canMirror == true
      items.push
        type: 'custom'
        html: "<strong>#{@translations.mirror}</strong>"
      
      items.push
        active: true
        label: @translations.mirror_off
        key: 'mirror'
        value: 'off'

      items.push
        active: false
        label: @translations.mirror_on
        key: 'mirror'
        value: 'on'

    if @canShowMask == true
      items.push
        type: 'custom'
        html: "<strong>#{@translations.overscan}</strong>"

      items.push
        active: @showMask == false
        label: @translations.overscan_on
        key: 'overscan'
        value: 'on'

      items.push
        active: @showMask == true
        label: @translations.overscan_off
        key: 'overscan'
        value: 'off'

    if @canShowZoom == true
      items.push
        type: 'custom'
        html: "<strong>#{@translations.zoom}</strong>"

      items.push
        active: @showZoom == false
        label: @translations.zoom_off
        key: 'zoom'
        value: 'off'

      items.push
        active: @showZoom == true
        label: @translations.zoom_on
        key: 'zoom'
        value: 'on'

    {
      className: 'select-vhh-video-player-settings'
      alignRight: true
      changeButton: false
      buttonLabel: '<i class="fa fa-cog"></i>'
      borderless: true
      items: items
    }

  # Create options for the fps dropdown
  getFpsOptions: ->
    items = []

    for value in @video.fpsOptions
      commas = value - Math.floor(value)

      labelValue = if "#{commas}".length > 4 then value.toFixed(2) else value

      items.push
        default: value == @currentFps
        active: value == @currentFps
        label: "#{labelValue} #{@translations.fps}"
        key: 'fps'
        value: value

    commas = @currentFps - Math.floor(@currentFps)

    labelValue = if "#{commas}".length > 4 then @currentFps.toFixed(2) else @currentFps

    {
      className: 'select-vhh-video-player-fps'
      changeButton: true
      buttonLabel: "#{labelValue} #{@translations.fps}"
      defaultLabel: @translations.default
      items: items
    }

  # Get the index of the HLS stream when the URL is given
  getHlsIndexBySrc: (src) ->
    for level, index in @hls.levels
      if level.url[0].indexOf(src) > -1
        return index

    return -1

  # Create options for the video counter type dropdown (frame, SMPTE, ...)
  getVideoCounterTypeOptions: ->
    items = []

    for value in @timeOptions
      items.push
        active: value == @currentCounterType
        label: @translations[value] or value
        key: 'counter-option'
        value: value

    {
      className: 'select-vhh-video-player-counter-type'
      changeButton: true
      buttonLabel: @translations.frame
      items: items
    }

  # Select next frame rate in the dropdown
  nextFrameRate: ->
    @$el.find('.select-vhh-video-player-fps .active').next().click()

  # Set up window.setInterval for simulating slow or reverse playback
  playByFrameInterval: ->
    intervalTime = Math.floor(1000 / @currentFps)
    @playbackIntervalId = window.setInterval(@updateFrameByInterval, intervalTime)

  # Select previous frame rate in the dropdown
  prevFrameRate: ->
    @$el.find('.select-vhh-video-player-fps .active').prev().click()

  # Remove big play button if present
  removePlayButtonBig: ->
    if @$playButtonBig?
      @$playButtonBig.off('click')

      @$playButtonBig.remove()
      delete @$playButtonBig

  # Seek in video
  seek: (value, type = 'frame') ->
    @removePlayButtonBig()

    targetTime = Math.max(@video.frameOffset, @video.convertToVideoTime(value, type, @$video[0].currentTime))

    if @video.lastFrameTime?
      targetTime = Math.min(targetTime, @video.lastFrameTime)

    @$video[0].currentTime = targetTime

  # Seek next frame according to current frame
  seekNextFrame: =>
    currentFrame = @video.formatVideoTime(@$video[0].currentTime);
    @seek(currentFrame + 1, 'frame')

  # Seek next shot according to current video position
  seekNextShot: =>
    shot = @video.getNextShot(@video.formatVideoTime(@$video[0].currentTime, 'frame'))
    
    if shot?
      @seek(shot.in, 'frame')

    else
      @seek(@video.lastFrameTime, 'float')

  # Seek previous frame according to current frame
  seekPrevFrame: =>
    currentFrame = @video.formatVideoTime(@$video[0].currentTime);
    @seek(currentFrame - 1, 'frame')

  # Seek previous shot according to current video position
  seekPrevShot: =>
    shot = @video.getPrevShot(@video.formatVideoTime(@$video[0].currentTime, 'frame'))
    
    if shot?
      @seek(shot.in, 'frame')

    else
      @seek(0, 'float')

  # Seek between 0 and 1 in video
  seekRelative: (relativeNumber = 0) ->
    relativeNumber = 0 if isNaN(relativeNumber) or relativeNumber < 0
    relativeNumber = Math.min 1, relativeNumber

    currentTime = @$video[0].duration * relativeNumber

    @$video[0].currentTime = currentTime
    @updateTimeline(currentTime)

  # Set the current audio volume
  setAudioVolume: (volume) ->
    if volume?
      volume = Math.max(Math.min(1, volume), 0)
      @$video[0].volume = volume

    else
      volume = @$video[0].volume

    icons = ['off', 'down', 'up']

    if volume == 0
      volumeIndex = 0

    else if volume < 0.75
      volumeIndex = 1

    else
      volumeIndex = 2

    $icon = @$audioVolumeButton.find('.fa')

    for icon, index in icons
      className = "fa-volume-#{icons[index]}"
      $icon.toggleClass(className, index == volumeIndex)

    @$audioVolumeBar.find('> div').css
      width: "#{Math.floor(volume * 100)}%"

  # Set default frame rate in the dropdown
  setDefaultFrameRate: ->
    @$el.find('.select-vhh-video-player-fps .default').click()

  # Called by the video mediator when a new frame has been selected from outside
  setCurrentFrame: (frameNumber) ->
    @seek(frameNumber, 'frame')

  # Set 1 fps in the dropdown
  setFrameRate1: ->
    @$el.find('.select-vhh-video-player-fps .vhh-video-player-menu-list-item[data-value="1"]').click()
  
  # Set 2 fps in the dropdown
  setFrameRate2: ->
    @$el.find('.select-vhh-video-player-fps .vhh-video-player-menu-list-item[data-value="2"]').click()
  
  # Set 6 fps in the dropdown
  setFrameRate6: ->
    @$el.find('.select-vhh-video-player-fps .vhh-video-player-menu-list-item[data-value="6"]').click()

  # Toggle video UI controls depending on the video state
  toggleControls: ->
    @$controls
      .toggleClass('playing', @playing)
      .toggleClass('playing-backward', @playBackward)

  # Based on the current state of @playing and related attributes, the video is
  # started or stopped
  togglePlaying: ->
    @removePlayButtonBig()
    @toggleControls()

    if @playing == true
      @updatePlaybackRate()

      if @playingByInterval == false
        @$video[0].play()

    else 
      if @playingByInterval == true
        @clearFrameInterval()
        
      else
        @$video[0].pause()

  # Fired by window.setInterval in order to jump to next or previous frame
  updateFrameByInterval: =>
    if @playBackward == true
      if @$video[0].currentTime == 0
        @playing = false
        @togglePlaying()

      else
        @seekPrevFrame()

    else
      if @$video[0].currentTime == @$video[0].duration
        @playing = false
        @togglePlaying()

      else
        @seekNextFrame()

  # Update the value of the counter input based on the current video time
  updateInputCounter: ->
    value = @video.formatVideoTime(@$video[0].currentTime, @currentCounterType)
    @$inputCounter.val(value)
  
  # Update the video playback rate and decide if natively play the video or use
  # window.setInterval for slow or reversed playback
  updatePlaybackRate: ->
    newRate = @currentFps / @video.fps
    
    @clearFrameInterval()
    @playingByInterval = @playBackward == true or newRate < @MIN_PLAYBACK_RATE

    if @playingByInterval == true
      @$video[0].pause()
      @playByFrameInterval() if @playing == true

    else
      @$video[0].playbackRate = newRate
      @$video[0].play() if @playing == true  
  
  # Update the timeline UI according to the current time
  updateTimeline: (currentTime) ->
    currentTime = @$video[0].currentTime unless currentTime?
    currentFrame = @video.formatVideoTime(currentTime, 'frame')

    @mediator?.updateFrame(currentFrame)

    @$timelineBar.css
      width: "#{100 * (@$video[0].currentTime / @$video[0].duration)}%"
  
  #############################################################################
  # Templates #################################################################
  ############################################################################# 

  # Attributes of data object:
  # - source: an object used for the video source (not for HLS)
  #   - type: mime-type of source
  #   - src: url of source
  # - counterOptions: options to be passed to the counter type menu
  # - fpsOptions: options to be passed to the FPS menu
  # - volume: the current audio volume in percent (0 - 100)
  # - settingsOptions: options to be passed to the settings menu
  # - translations: the translations object
  mainTemplate: (data) ->
    result = []

    result.push("<div id=\"#{data.id}\" class=\"vhh-video-player-wrapper vhh-root-node\">")
    
    result.push('<div class="vhh-video-player-frame-wrapper">')
    result.push('<div class="vhh-video-player-mask">')
    result.push("<video class=\"vhh-video-player-canvas\"#{data.videoAttributes} oncontextmenu=\"return false;\">")
    result.push("<source src=\"#{data.source.src}\" type=\"#{data.source.type}\">") if data.source?
    result.push('</video>')
    result.push('</div>')
    
    if data.canShowMask
      showMaskString = if data.showMask then ' vhh-video-mask-show' else '';
      left = Math.floor(data.mask.left * 100)
      right = Math.floor(data.mask.right * 100)
      top = Math.floor(data.mask.top * 100)
      bottom = Math.floor(data.mask.bottom * 100)
      result.push("<div class=\"vhh-video-mask#{showMaskString}\"><div style=\"height: #{top}%;\"></div><div style=\"top: #{top}%; bottom: #{bottom}%; width: #{right}%;\"></div><div style=\"height: #{bottom}%;\"></div><div style=\"top: #{top}%; bottom: #{bottom}%; width: #{left}%\"></div></div>")
    
    result.push('<div class="vhh-video-player-big-button-play"><i class="fa fa-play"></i></div>')
    result.push('</div>')
    
    result.push('<div class="vhh-video-player-controls">')
    
    result.push('<div class="vhh-video-player-timeline-wrapper">')
    result.push('<div class="vhh-video-player-timeline">')
    result.push('<div class="vhh-video-player-timeline-bar">')
    result.push('<div class="vhh-video-player-timeline-grip"></div>')
    result.push('</div></div></div>')

    result.push('<div class="vhh-video-player-controls-row clearfix">')
    
    result.push('<div class="vhh-video-player-col-left">')
    result.push(@menuTemplate(data.counterOptions))
    result.push(' <input class="vhh-video-player-input-counter" type="text" data-type="frame" value="1" /> ')
    result.push(@menuTemplate(data.fpsOptions))
    result.push('</div>')

    result.push('<div class="vhh-video-player-col-center">')
    result.push("<button class=\"vhh-video-player-button vhh-video-player-button-prev-shot\" type=\"button\" title=\"#{data.translations.video_button_prev_shot}\"><i class=\"fa fa-backward\"></i></button>")
    result.push("<button class=\"vhh-video-player-button vhh-video-player-button-prev-frame\" type=\"button\" title=\"#{data.translations.video_button_prev_frame}\"><i class=\"fa fa-step-backward\"></i></button>")
    result.push("<button class=\"vhh-video-player-button vhh-video-player-button-play-backward\" type=\"button\" title=\"#{data.translations.video_button_play_reverse}\"><i class=\"fa fa-play\"></i><i class=\"fa fa-pause\"></i></button>")
    result.push("<button class=\"vhh-video-player-button vhh-video-player-button-play\" type=\"button\" title=\"#{data.translations.video_button_play}\"><i class=\"fa fa-play\"></i><i class=\"fa fa-pause\"></i></button>")
    result.push("<button class=\"vhh-video-player-button vhh-video-player-button-next-frame\" type=\"button\" title=\"#{data.translations.video_button_next_frame}\"><i class=\"fa fa-step-forward\"></i></button>")
    result.push("<button class=\"vhh-video-player-button vhh-video-player-button-next-shot\" type=\"button\" title=\"#{data.translations.video_button_next_shot}\"><i class=\"fa fa-forward\"></i></button>")
    result.push('</div>')

    result.push('<div class="vhh-video-player-col-right">')
    result.push(@audioTemplate(data.volume))
    result.push(@menuTemplate(data.settingsOptions))
    result.push("<button class=\"vhh-video-player-button vhh-video-player-button-fullscreen\" type=\"button\" title=\"#{data.translations.video_button_fullscreen}\"><i class=\"fa fa-expand\"></i><i class=\"fa fa-compress\"></i></button>")
    result.push('</div>')
    
    result.push('</div>')
    result.push('</div>')
    result.push('</div>')

    result.join('')

  audioTemplate: (volumePercent) =>
    result = []
    
    result.push('<div class="vhh-video-player-audio">')
    result.push('<div class="vhh-video-player-audio-bar">')
    result.push("<div style=\"width: #{volumePercent}%;\">")
    result.push('<div class="vhh-video-player-audio-grip"></div>')
    result.push('</div>')
    result.push('</div>')
    result.push("<button class=\"vhh-video-player-button vhh-video-player-audio-button\" type=\"button\" title=\"#{@translations.audio_button}\"><i class=\"fa\"></i></button>")
    result.push('</div>')

    result.join('')

  # Attributes of data object:
  # - borderless: if true, menu button has no border
  # - changeButton: if true, button text is changed according to selected item
  # - alignRight: if true, dropdown menu is right-aligned relative to menu button
  # - items: a list of items shown in the menu
  #   - type: if "custom", custom HTML is included. If not "custom", a menu item is shown
  #   - html: used for type "custom" in order to include html
  #   - active: if true, marked as active menu item
  #   - default: if true, marked as default menu item
  #   - defaultLabel: if assigned and default is true, this text for is appended
  menuTemplate: (data) ->
    result = []

    result.push("<div class=\"vhh-video-player-menu #{data.className}")
    result.push(" no-border") if data.borderless
    result.push('"')
    result.push(' data-change-button="true"') if data.changeButton
    result.push('>')
    result.push("<button type=\"button\" class=\"vhh-video-player-button\"><span>#{data.buttonLabel}</span></button>")
    result.push('<div class="vhh-video-player-menu-list')
    result.push(' align-right') if data.alignRight
    result.push('">')

    for item in data.items
      switch item.type
        when 'custom'
          result.push("<div class=\"vhh-video-player-menu-list-item custom\">#{item.html}</div>")

        else
          result.push("<button type=\"button\" data-key=\"#{item.key}\" data-value=\"#{item.value}\" class=\"vhh-video-player-menu-list-item")
          
          result.push(' active') if item.active
          result.push(' default') if item.default
          result.push("\"><span class=\"circle\"></span><span class=\"text\">#{item.label}</span>")
          result.push(" (#{item.defaultLabel})") if item.defaultLabel?
          result.push('</button>')

    result.push('</div>')
    result.push('</div>')

    result.join('')

  #############################################################################
  # Classes ###################################################################
  #############################################################################

  # This class represents the video metadata and not the HTML video element
  @Video: class Video
    # Different fps options should be available for playback
    FPS_OPTIONS: [1, 2, 6, 12, 16, 18, 20, 22, 24, 25, 36, 48]

    # Acording to the type of film, the film lengths are different
    FILM_LENGTHS:
      'S8mm': 4.234
      'N8mm': 3.8025
      '9.5mm': 7.5415
      '16mm': 7.605
      '35mm': 19.000
      '35mm/3Perf': 14.250
      '35mm/2Perf': 9.5
      '65mm': 23.750
      'IMAX': 71.250
    
    # FPS (frames per second) of the video
    fps: 24

    constructor: (data) ->
      @fps = Number(data.fps)
      @fps = 24 if isNaN(@fps) or @fps < 1 or @fps > 60

      @fpsOptions = @FPS_OPTIONS.slice()

      # If this is unusual fps, insert into options
      unless @fps in @fpsOptions
        foundIndex = @fpsOptions.length

        for fpsOption, index in @fpsOptions
          if @fps < fpsOption
            foundIndex = index
            break

        @fpsOptions.splice(foundIndex, 0, @fps)

      @source = data.source
      @hls = data.hls
      @frameLength = 1 / @fps
      @frameOffset = @frameLength * (data.frameOffset or 0)
      @shots = data.shots
      @filmFormat = data.filmFormat
      @mask = data.mask

      if data.frames?
        @frames = data.frames
        @lastFrameTime = @frameLength * (data.frames - 1) + (@frameLength / 4) + @frameOffset

    hasShots: ->
      @shots? and @shots.length > 0

    padStart: (value, length, character) ->
      value = "#{value}"

      return value if value.length >= length

      while value.length < length
        value = "#{character}#{value}"

      value

    formatVideoTime: (timeAsFloat, type = 'frame') ->
      return '-' if isNaN(timeAsFloat)
      
      timeAsFloat = Math.min(timeAsFloat, @lastFrameTime) if @lastFrameTime?

      switch type
        when 'frame'
          result = Math.floor((timeAsFloat - @frameOffset + (@frameLength * 0.25)) / @frameLength) + 1

          #result = Math.floor((timeAsFloat - @frameOffset) / @frameLength) + 1
          result = Math.min(result, @frames) if @frames?
          result = Math.max(1, result)
          result

        when 'smpte'
          seconds = Math.floor(timeAsFloat)
          frames = @formatVideoTime(timeAsFloat - seconds, 'frame')

          minutes = Math.floor(seconds / 60)
          seconds = seconds - (minutes * 60)

          hours = Math.floor(minutes / 60)
          minutes = minutes - (hours * 60)

          hours = @padStart(hours, 2, '0')
          minutes = @padStart(minutes, 2, '0')
          seconds = @padStart(seconds, 2, '0')
          frames = @padStart(frames, 2, '0')

          "#{hours}:#{minutes}:#{seconds}.#{frames}"

        when 'meter'
          @getFilmLength(timeAsFloat).toFixed(2)

        when 'inch'
          result = @getFilmLength(timeAsFloat) * 3.2807322594
          result.toFixed(1)

        when 'simple'
          seconds = Math.floor(timeAsFloat)

          minutes = Math.floor(seconds / 60)
          seconds = seconds - (minutes * 60)

          hours = Math.floor(minutes / 60)
          minutes = minutes - (hours * 60)

          minutes = @padStart(minutes, 2, '0')
          seconds = @padStart(seconds, 2, '0')

          if hours > 0
            hours = @padStart(hours, 2, '0')
            "#{hours}:#{minutes}:#{seconds}"

          else
            "#{minutes}:#{seconds}"

        else
          timeAsFloat.toFixed(3)

    convertToVideoTime: (value, type = 'frame', fallBackValue = 0) ->
      switch type
        when 'frame'
          value = parseInt(value)
          
          return fallBackValue if isNaN(value)

          @frameLength * (value - 1) + (@frameLength * 0.25) + @frameOffset

        when 'smpte'
          value = "#{value}"
          regEx = /^(\d\d):(\d\d):(\d\d).(\d\d)$/
          match = regEx.exec(value)

          return fallBackValue unless match?
          
          hours = parseInt(match[1])
          minutes = parseInt(match[2])
          seconds = parseInt(match[3])
          frames = parseInt(match[4])

          return fallBackValue if isNaN(hours) or isNaN(minutes) or isNaN(seconds) or isNaN(frames)

          frames = Math.max(0, frames - 1)

          (((hours * 60) + minutes) * 60) + seconds + (frames * @frameLength)

        when 'meter'
          value = Number(value)
          return fallBackValue if isNaN(value)

          @getFloatFromFilmLength(value)

        when 'inch'
          value = Number(value)
          return fallBackValue if isNaN(value)

          @getFloatFromFilmLength(value) / 3.2807322594

        when 'simple'
          value = "#{value}"
          seconds = 0

          if value.length < 3
            return fallBackValue if isNaN(value)
            value

          else if value.length < 6
            regEx = /^(\d{1,2}):(\d{1,2})$/
            match = regEx.exec(value)

            return fallBackValue unless match?

            minutes = parseInt(match[1])
            seconds = parseInt(match[2])

            return fallBackValue if isNaN(minutes) or isNaN(seconds)

            (minutes * 60) + seconds

          else
            regEx = /^(\d{1,2}):(\d{1,2}):(\d{1,2})$/

            match = regEx.exec(value)

            return fallBackValue unless match?

            hours = parseInt(match[1])
            minutes = parseInt(match[2])
            seconds = parseInt(match[3])

            return fallBackValue if isNaN(hours) orisNaN(minutes) or isNaN(seconds)

            (((hours * 60) + minutes) * 60) + seconds

        else
          value = Number(value)
          return fallBackValue if isNaN(value)

          value
    
    getHlsByResolution: (key = 'auto') ->
      key = key.toLowerCase()

      for item in @hls
        return item if item.resolution.toLowerCase() == key

      null

    getHlsByUrl: (url) ->
      for item in @hls
        return item if url.indexOf(item.src) > -1

      null

    getFilmLength: (timeAsFloat) ->
      return 0 unless @filmFormat? and @FILM_LENGTHS[@filmFormat]?
      
      filmLength = @FILM_LENGTHS[@filmFormat] or 0
      timeAsFloat * @fps * filmLength / 1000

    getFloatFromFilmLength: (currentFilmLength) ->
      return 0 unless @filmFormat? and @FILM_LENGTHS[@filmFormat]?

      filmLength = @FILM_LENGTHS[@filmFormat] or 0
      (currentFilmLength * 1000) / (@fps * filmLength)

    getCurrentShotIndex: (frame) ->
      return null unless @hasShots()

      for shot, index in @shots
        return index if shot.in <= frame and shot.out >= frame

      null

    getLastShotFrame: ->
      result = 0

      for shot, index in @shots
        result = Math.max(result, shot.out)

      result

    getFirstShotFrame: ->
      result = @shots[0].in

      for shot, index in @shots
        result = Math.min(result, shot.in)

      result

    getPrevShot: (frame) ->
      return null unless @hasShots()

      shotIndex = @getCurrentShotIndex(frame)
      
      if shotIndex?
        @shots[Math.max(0, shotIndex - 1)]

      else if frame > @getLastShotFrame()
        @shots[@shots.length - 1]

      else
        null

    getNextShot: (frame) ->
      return null unless @hasShots()

      shotIndex = @getCurrentShotIndex(frame)

      if shotIndex?
        @shots[Math.min(shotIndex + 1, @shots.length - 1)]

      else if frame < @getFirstShotFrame()
        @shots[0]

      else
        null
