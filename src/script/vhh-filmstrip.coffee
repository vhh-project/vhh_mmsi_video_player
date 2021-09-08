window.VhhFilmstrip = class VhhFilmstrip
  # How many images should be preloaded concurrently
  MAX_THUMBS_AT_ONCE: 50

  # Width of every thumb
  THUMB_WIDTH: 120

  constructor: (data) ->
    # Remember the container in order to attach the player to it
    @$container = $(data.container)

    # Mediator that allows communication for between video and other UI components
    @mediator = data.mediator
    @mediator.subscribe('frameUpdate', @)

    # Number of first frame
    @firstFrameNumber = data.firstFrameNumber or 1

    # Number of last frame
    @lastFrameNumber = data.lastFrameNumber or 2

    # Current thumb index
    @currentFrameNumber = data.currentFrameNumber or @firstFrameNumber

    # If true, the filmstrip scrolls along while playing
    @follow = data.follow != false

    # Path to images, while numbering is designated with %s
    @path = data.path

    # How many digits are used in the thumb name, e.g. thumb0001.jpg das 4 digits.
    @pathDigits = data.pathDigits

    @render()

  # Renders the UI, and sets frequently used DOM elements
  render: ->
    totalWidth = (@THUMB_WIDTH + 1) * @lastFrameNumber

    html = ['<div class="vhh-filmstrip-wrapper noselect vhh-root-node">']
    html.push("<div class=\"vhh-filmstrip-inner\" style=\"width: #{totalWidth}px\">")
    html.push('</div></div>')

    @$container.html(html.join(''))

    @$el = @$container.find('> .vhh-filmstrip-wrapper')
    @$el.scrollLeft(0)

    @$inner = @$el.find('.vhh-filmstrip-inner')

    @attachEvents()
    @updateThumbImages()
    @setCurrentFrame(@currentIndex)

  # Attaches UI events on DOM elements
  attachEvents: ->
    @$el.find('.vhh-filmstrip-inner').on('click', @clickTimeline)
    @$el.on('scroll', @scrollTimeline)

  # Detaches UI events from DOM elements
  detachEvents: ->
    @$el.find('.vhh-filmstrip-inner').off('click')
    @$el.off('scroll')

  remove: ->
    @detachEvents()
    @mediator.unsubscribe('frameUpdate', @)

    @$el.remove()

  #############################################################################
  # UI Handlers ###############################################################
  #############################################################################

  clickTimeline: (event) =>
    frameNumber = Math.floor(Math.floor(event.pageX - @$el.offset().left + @$el.scrollLeft()) / (@THUMB_WIDTH + 1) + 1)
    
    @setCurrentFrame(frameNumber, false)
    @mediator.setFrame(frameNumber)

  scrollTimeline: (event) =>
    @updateThumbImages()

  #############################################################################
  # Custom and Helper Methods #################################################
  #############################################################################

  followCurrentFrame: (index) ->
    return unless index? or @$activeThumb?.length > 0

    unless index?
      index = @$activeThumb.data('index')

    targetLeft = index * (@THUMB_WIDTH + 1) - ((@$el.width() + @$activeThumb.width()) / 2)
    targetLeft = Math.max(0, targetLeft)
    
    @$el.scrollLeft(targetLeft)

  # Called by the video mediator
  frameUpdate: (frameNumber) ->
    @setCurrentFrame(frameNumber, true)

  # Get the path of the thumb depending on the index
  getThumbPath: (index = 1) ->
    paddedIndex = @padStart(index, @pathDigits, '0')
    @path.replace('%s', paddedIndex)

  # Padding for strings
  padStart: (value, length, character) ->
    value = "#{value}"

    return value if value.length >= length

    while value.length < length
      value = "#{character}#{value}"

    value

  setCurrentFrame: (frameNumber, follow) ->
    return if @currentFrameNumber == frameNumber

    @currentFrameNumber = frameNumber
    @$activeThumb?.removeClass('active')

    @followCurrentFrame(@currentFrameNumber)   
    @updateThumbImages()

    @$activeThumb = @$inner.find(".vhh-filmstrip-thumb-#{frameNumber}")
    @$activeThumb.addClass('active')

    @followCurrentFrame() if follow == true and @follow

  updateThumbImages: ->
    frameNumberLeft = Math.floor(@$el.scrollLeft() / (@THUMB_WIDTH + 1)) + 1

    framesAlreadySet = @minFrame? and @maxFrame?
    
    newMinFrame = Math.max(1, frameNumberLeft - Math.floor(@MAX_THUMBS_AT_ONCE / 2))
    newMaxFrame = Math.min(@lastFrameNumber, newMinFrame + @MAX_THUMBS_AT_ONCE - 1)

    if framesAlreadySet
      for index in [@minFrame .. @maxFrame]
        if index < newMinFrame or index > newMaxFrame
          @$inner.find(".vhh-filmstrip-thumb-#{index}").remove()

    for index in [newMinFrame .. newMaxFrame]
      if (not framesAlreadySet) or (index < @minFrame or index > @maxFrame)
        @$inner.append(@thumbTemplate(index))

    @minFrame = newMinFrame
    @maxFrame = newMaxFrame

  #############################################################################
  # Templates #################################################################
  ############################################################################# 

  thumbTemplate: (index) ->
    left = (@THUMB_WIDTH + 1) * (index - 1)
    path = @getThumbPath(index)

    html = []
    html.push("<div class=\"vhh-filmstrip-thumb vhh-filmstrip-thumb-#{index}\" data-index=\"#{index}\" style=\"left: #{left}px;\">")
    html.push("<img src=\"#{path}\" />")
    html.push("<div class=\"vhh-filmstrip-number\">#{index}</div>")
    html.push('</div>')
    html.join('')
  
