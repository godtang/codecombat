CocoView = require 'views/core/CocoView'
template = require 'templates/play/level/level-dialogue-view'
DialogueAnimator = require './DialogueAnimator'

module.exports = class LevelDialogueView extends CocoView
  id: 'level-dialogue-view'
  template: template

  subscriptions:
    'sprite:speech-updated': 'onSpriteDialogue'
    'level:sprite-clear-dialogue': 'onSpriteClearDialogue'
    'level:shift-space-pressed': 'onShiftSpacePressed'
    'level:escape-pressed': 'onEscapePressed'
    'sprite:dialogue-sound-completed': 'onDialogueSoundCompleted'

  events:
    'click': 'onClick'
    'click a': 'onClickLink'

  constructor: (options) ->
    super options
    @level = options.level
    @sessionID = options.sessionID

  onClick: (e) ->
    Backbone.Mediator.publish 'tome:focus-editor', {}

  onClickLink: (e) ->
    route = $(e.target).attr('href')
    if route and /item-store/.test route
      PlayItemsModal = require 'views/play/modal/PlayItemsModal'
      @openModalView new PlayItemsModal supermodel: @supermodal
      e.stopPropagation()

  shouldSkipDialogue: (mood) ->
    return false if me.isAdmin()
    return true if mood is 'alarm'
    if mood is 'debrief'
      switch me.get('testGroupNumber') % 8
        when 4, 5, 6, 7 then return true # First 4 test groups do not see 'debrief'-type boxes 
    return false

  onSpriteDialogue: (e) ->
    return unless e.message
    return Backbone.Mediator.publish('script:end-current-script', {}) if @shouldSkipDialogue(e.mood)
    @$el.addClass 'active speaking'
    $('body').addClass('dialogue-view-active')
    @setMessage e.message, e.mood, e.responses
    if e.mood is 'debrief'
      if e.sprite.thangType.get('poseImage')?
        @$el.find('.dialogue-area').append($('<img/>').addClass('embiggen').attr('src', '/file/' + e.sprite.thangType.get('poseImage')))
      else
        @$el.find('.dialogue-area').append($('<img/>').attr('src', e.sprite.thangType.getPortraitURL()))
    window.tracker?.trackEvent 'Heard Sprite', {message: e.message, label: e.message, ls: @sessionID}

  onDialogueSoundCompleted: ->
    @$el.removeClass 'speaking'

  onSpriteClearDialogue: ->
    @$el.removeClass 'active speaking'
    $('body').removeClass('dialogue-view-active')
    @$el.find('img').remove()
    @$el.removeClass(@lastMood) if @lastMood

  setMessage: (message, mood, responses) ->
    message = marked message
    # Fix old HTML icons like <i class='icon-play'></i> in the Markdown
    message = message.replace /&lt;i class=&#39;(.+?)&#39;&gt;&lt;\/i&gt;/, "<i class='$1'></i>"
    clearInterval(@messageInterval) if @messageInterval
    @bubble = $('.dialogue-bubble', @$el)
    @$el.removeClass(@lastMood) if @lastMood
    @$el.find('img').remove()
    @$el.addClass(mood)
    @lastMood = mood
    @bubble.text('')
    group = $('<div class="enter secret"></div>')
    @bubble.append(group)
    if responses
      @lastResponses = responses
      for response in responses
        button = $('<button class="btn btn-small banner"></button>').text(response.text)
        button.addClass response.buttonClass if response.buttonClass
        group.append(button)
        response.button = $('button:last', group)
    else
      s = $.i18n.t('common.continue', defaultValue: 'Continue')
      sk = $.i18n.t('play_level.skip_tutorial', defaultValue: 'skip: esc')
      if not @escapePressed and not @isFullScreen()
        group.append('<span class="hud-hint">' + sk + '</span>')
      group.append($('<button class="btn btn-small banner with-dot">' + s + ' <div class="dot"></div></button>'))
      @lastResponses = null
    @animator = new DialogueAnimator(message, @bubble)
    @messageInterval = setInterval(@addMoreMessage, 1000 / 30)  # 30 FPS

  isFullScreen: ->
    document.fullScreen || document.mozFullScreen || document.webkitIsFullScreen

  addMoreMessage: =>
    if @animator.done()
      clearInterval(@messageInterval)
      @messageInterval = null
      $('.enter', @bubble).removeClass('secret').css('opacity', 0.0).delay(500).animate({opacity: 1.0}, 500, @animateEnterButton)
      if @lastResponses
        buttons = $('.enter button')
        for response, i in @lastResponses
          channel = response.channel.replace 'level-set-playing', 'level:set-playing'  # Easier than migrating all those victory buttons.
          f = (r) => => setTimeout((-> Backbone.Mediator.publish(channel, r.event or {})), 10)
          $(buttons[i]).click(f(response))
      else
        $('.enter', @bubble).click(-> Backbone.Mediator.publish('script:end-current-script', {}))
      return
    @animator.tick()

  onShiftSpacePressed: (e) ->
    @shiftSpacePressed = (@shiftSpacePressed || 0) + 1
    # We don't need to handle script:end-current-script--that's done--but if we do have
    # custom buttons, then we need to trigger the one that should fire (the last one).
    # If we decide that always having the last one fire is bad, we should make it smarter.
    return unless @lastResponses?.length
    r = @lastResponses[@lastResponses.length - 1]
    channel = r.channel.replace 'level-set-playing', 'level:set-playing'
    _.delay (-> Backbone.Mediator.publish(channel, r.event or {})), 10

  onEscapePressed: (e) ->
    @escapePressed = true

  animateEnterButton: =>
    return unless @bubble
    button = $('.enter', @bubble)
    dot = $('.dot', button)
    dot.animate({opacity: 0.2}, 300).animate({opacity: 1.9}, 600, @animateEnterButton)

  destroy: ->
    clearInterval(@messageInterval) if @messageInterval
    super()
