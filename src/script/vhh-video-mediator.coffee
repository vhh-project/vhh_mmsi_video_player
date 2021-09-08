window.VhhVideoMediator = class VhhVideoMediator
  constructor: (data) ->
    @videoPlayer = data?.videoPlayer

    @subscribers =
      frameUpdate: []

  getListByType: (type) ->
    switch type
      when 'frameUpdate'
        @subscribers.frameUpdate

      else
        null

  subscribe: (type, model) ->
    list = @getListByType(type)
    return false unless list?

    list.push(model)

  unsubscribe: (type, model) ->
    list = @getListByType(type)
    return false unless list?

    for item, index in list
      if item == model
        list.splice(index, 1)
        return true

    false

  updateFrame: (frameNumber) ->
    for item in @getListByType('frameUpdate')
      item.frameUpdate?(frameNumber)

  setFrame: (frameNumber) ->
    @videoPlayer?.setCurrentFrame(frameNumber)




