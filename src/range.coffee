ancestors = require('ancestors')
matches = require('matches-selector')
xpath = require('./xpath')
Util = require('./util')

Range = {}

# Public: Determines the type of Range of the provided object and returns
# a suitable Range instance.
#
# r - A range Object.
#
# Examples
#
#   selection = window.getSelection()
#   Range.sniff(selection.getRangeAt(0))
#   # => Returns a BrowserRange instance.
#
# Returns a Range object or false.
Range.sniff = (r) ->
  if r.commonAncestorContainer?
    new Range.BrowserRange(r)
  else if typeof r.start is "string"
    new Range.SerializedRange(r)
  else if r.start and typeof r.start is "object"
    new Range.NormalizedRange(r)
  else
    false

class Range.RangeError
  constructor: (@type, @message, @parent = null) ->
    @stack = (new Error()).stack

  # The Error built-in cannot be invoked with .apply() so we can't use super.
  @:: = new Error
  @::constructor = @


# Public: Creates a wrapper around a range object obtained from a DOMSelection.
class Range.BrowserRange

  # Public: Creates an instance of BrowserRange.
  #
  # object - A range object obtained via DOMSelection#getRangeAt().
  #
  # Examples
  #
  #   selection = window.getSelection()
  #   range = new Range.BrowserRange(selection.getRangeAt(0))
  #
  # Returns an instance of BrowserRange.
  constructor: (obj) ->
    @commonAncestorContainer = obj.commonAncestorContainer
    @startContainer          = obj.startContainer
    @startOffset             = obj.startOffset
    @endContainer            = obj.endContainer
    @endOffset               = obj.endOffset

  splitBoundaries: ->
    if @endContainer.nodeType is Util.NodeTypes.TEXT_NODE
      if 0 < @endOffset < @endContainer.length
        if @startContainer is @endContainer
          @commonAncestorContainer = @endContainer.parentNode
          @endContainer = @endContainer.splitText(@endOffset)

          if @endOffset <= @startOffset
            @startContainer = @endContainer
            @startOffset -= @endOffset

          @endOffset = 0
        else
          @endContainer = @endContainer.splitText(@endOffset)
          @endOffset = 0

    if @startContainer.nodeType is Util.NodeTypes.TEXT_NODE
      if 0 < @startOffset < @startContainer.length
        if @commonAncestorContainer is @startContainer
          @commonAncestorContainer = @commonAncestorContainer.parentNode

        if @startContainer is @endContainer
          @commonAncestorContainer = @startContainer.parentNode
          @startContainer = @startContainer.splitText(@startOffset)

          if @startOffset <= @endOffset
            @endContainer = @startContainer
            @endOffset -= @startOffset

          @startOffset = 0
        else
          @startContainer = @startContainer.splitText(@startOffset)
          @startOffset = 0

  # Public: Normalize the start and end to TextNode boundaries.
  #
  # Returns an instance of Range.NormalizedRange
  normalize: (root) ->
    this.splitBoundaries()

    # Initialize the result.
    commonAncestor = null
    start = null
    end = null

    # Find a common ancestor Element.
    commonAncestor = @commonAncestorContainer
    while commonAncestor.nodeType isnt Util.NodeTypes.ELEMENT_NODE
      commonAncestor = commonAncestor.parentNode

    # Get (a copy of) the boundaries of the range.
    {startContainer, startOffset, endContainer, endOffset} = this

    # Move the start container to the last leaf before any sibling boundary.
    # All children of the start container will fall within the range.
    # This step obviates the recursion when iterating over the text.
    while startContainer.childNodes.length and startOffset > 0
      startContainer = startContainer.childNodes[startOffset-1]
      startOffset = startContainer.length or startContainer.childNodes.length

    # Find the first TextNode.
    node = startContainer
    while node?
      # Skip to the first leaf Node, since all children are included.
      # This step substitutes for recursion, capitalizing on the preconditions.
      while node.firstChild?
        node = node.firstChild

      # Terminate on the first TextNode not excluded by the offset.
      if node.nodeType is Util.NodeTypes.TEXT_NODE
        if not (node is startContainer and startOffset isnt 0)
          start = node
          break

      # Skip to the next branch, staying within the common ancestor.
      while not (node.nextSibling? or node is commonAncestor)
        node = node.parentNode

      node = node.nextSibling

    # Move the end container to the first leaf before any sibling boundary.
    # All children of the end container will fall within the range.
    # This step obviates the recursion when iterating over the text in reverse.
    while endOffset < endContainer.childNodes.length
      endContainer = endContainer.childNodes[endOffset]
      endOffset = 0

    # Find the last TextNode.
    node = endContainer
    while node?
      # Skip to the last leaf Node, since all children are included.
      # This step substitutes for recursion, capitalizing on the preconditions.
      while node.lastChild?
        node = node.lastChild

      # Terminate on the first TextNode not excluded by the offset.
      if node.nodeType is Util.NodeTypes.TEXT_NODE
        if not (node is endContainer and endOffset is 0)
          end = node
          break

      # Skip to the previous branch, staying within the common ancestor.
      while not (node.previousSibling? or node is commonAncestor)
        node = node.parentNode

      node = node.previousSibling

    return new Range.NormalizedRange({commonAncestor, start, end})

  # Public: Creates a range suitable for storage.
  #
  # root           - A root Element from which to anchor the serialisation.
  # ignoreSelector - A selector String of elements to ignore. For example
  #                  elements injected by the annotator.
  #
  # Returns an instance of SerializedRange.
  serialize: (root, ignoreSelector) ->
    this.normalize(root).serialize(root, ignoreSelector)

# Public: A normalised range is most commonly used throughout the annotator.
# its the result of a deserialised SerializedRange or a BrowserRange with
# out browser inconsistencies.
class Range.NormalizedRange

  # Public: Creates an instance of a NormalizedRange.
  #
  # This is usually created by calling the .normalize() method on one of the
  # other Range classes rather than manually.
  #
  # obj - An Object literal. Should have the following properties.
  #       commonAncestor: A Node that contains the start Node and end Node.
  #       start:          The first TextNode in the range.
  #       end             The last TextNode in the range.
  #
  # Returns an instance of NormalizedRange.
  constructor: (obj) ->
    @commonAncestor = obj.commonAncestor
    @start          = obj.start
    @end            = obj.end

  # Public: For API consistency.
  #
  # Returns itself.
  normalize: (root) ->
    this

  # Public: Limits the nodes within the NormalizedRange to those contained
  # withing the bounds parameter. It returns an updated range with all
  # properties updated. NOTE: Method returns null if all nodes fall outside
  # of the bounds.
  #
  # bounds - An Element to limit the range to.
  #
  # Returns updated self or null.
  limit: (bounds) ->
    if @commonAncestor == bounds or Util.contains(bounds, @commonAncestor)
      return this

    if not Util.contains(@commonAncestor, bounds)
      return null

    document = bounds.ownerDocument

    if not Util.contains(bounds, @start)
      w = document.createTreeWalker(bounds, NodeFilter.SHOW_TEXT, null, false)
      @start = w.firstChild()

    if not Util.contains(bounds, @end)
      w = document.createTreeWalker(bounds, NodeFilter.SHOW_TEXT, null, false)
      @end = w.lastChild()

    return null unless @start and @end

    startParents = ancestors(@start)
    for parent in ancestors(@end)
      if startParents.indexOf(parent) != -1
        @commonAncestor = parent
        break
    this

  # Convert this range into an object consisting of two pairs of (xpath,
  # character offset), which can be easily stored in a database.
  #
  # root - The root Element relative to which XPaths should be calculated
  # ignoreSelector - A selector String of elements to ignore. For example
  #                  elements injected by the annotator.
  #
  # Returns an instance of SerializedRange.
  serialize: (root, ignoreSelector) ->

    serialization = (node, isEnd) ->
      if ignoreSelector
        filterFn = (node) -> not matches(node, ignoreSelector)
        origParent = ancestors(node, filterFn)[0]
      else
        origParent = node.parentNode

      path = xpath.fromNode(origParent, root)
      textNodes = Util.getTextNodes(origParent)

      # Calculate real offset as the combined length of all the
      # preceding textNode siblings. We include the length of the
      # node if it's the end node.
      nodes = textNodes.slice(0, textNodes.indexOf(node))
      offset = 0
      for n in nodes
        offset += n.nodeValue.length

      if isEnd then [path, offset + node.nodeValue.length] else [path, offset]

    start = serialization(@start)
    end   = serialization(@end, true)

    new Range.SerializedRange({
      # XPath strings
      start: start[0]
      end: end[0]
      # Character offsets (integer)
      startOffset: start[1]
      endOffset: end[1]
    })

  # Public: Creates a concatenated String of the contents of all the text nodes
  # within the range.
  #
  # Returns a String.
  text: ->
    (for node in this.textNodes()
      node.nodeValue
    ).join ''

  # Public: Fetches only the text nodes within the range.
  #
  # Returns an Array of TextNode instances.
  textNodes: ->
    textNodes = Util.getTextNodes(this.commonAncestor)
    [start, end] = [textNodes.indexOf(this.start), textNodes.indexOf(this.end)]
    # Return the textNodes that fall between the start and end indexes.
    return textNodes[start..end]

# Public: A range suitable for storing in local storage or serializing to JSON.
class Range.SerializedRange

  # Public: Creates a SerializedRange
  #
  # obj - The stored object. It should have the following properties.
  #       start:       An xpath to the Element containing the first TextNode
  #                    relative to the root Element.
  #       startOffset: The offset to the start of the selection from obj.start.
  #       end:         An xpath to the Element containing the last TextNode
  #                    relative to the root Element.
  #       startOffset: The offset to the end of the selection from obj.end.
  #
  # Returns an instance of SerializedRange
  constructor: (obj) ->
    @start       = obj.start
    @startOffset = obj.startOffset
    @end         = obj.end
    @endOffset   = obj.endOffset

  # Public: Creates a NormalizedRange.
  #
  # root - The root Element from which the XPaths were generated.
  #
  # Returns a NormalizedRange instance.
  normalize: (root) ->
    range = {}

    for p in ['start', 'end']
      try
        node = xpath.toNode(this[p], root)
      catch e
        throw new Range.RangeError(
          p,
          "Error while finding #{p} node: #{this[p]}: " + e,
          e
        )

      if not node
        throw new Range.RangeError(p, "Couldn't find #{p} node: #{this[p]}")

      # Unfortunately, we *can't* guarantee only one textNode per
      # elementNode, so we have to walk along the element's textNodes until
      # the combined length of the textNodes to that point exceeds or
      # matches the value of the offset.
      length = 0
      targetOffset = this[p + 'Offset']

      # Range excludes its endpoint because it describes the boundary position.
      # Target the string index of the last character inside the range.
      if p is 'end' then targetOffset -= 1

      for tn in Util.getTextNodes(node)
        if (length + tn.nodeValue.length > targetOffset)
          range[p + 'Container'] = tn
          range[p + 'Offset'] = this[p + 'Offset'] - length
          break
        else
          length += tn.nodeValue.length

      # If we fall off the end of the for loop without having set
      # 'startOffset'/'endOffset', the element has shorter content than when
      # we annotated, so throw an error:
      if not range[p + 'Offset']?
        throw new Range.RangeError(
          "#{p}offset",
          "Couldn't find offset #{this[p + 'Offset']} in element #{this[p]}"
        )

    for node in ancestors(range.startContainer)
      if range.endContainer.nodeType == Util.NodeTypes.TEXT_NODE
        endContainer = range.endContainer.parentNode
      else
        endContainer = range.endContainer

      if Util.contains(node, endContainer)
        range.commonAncestorContainer = node
        break

    new Range.BrowserRange(range).normalize(root)

  # Public: Creates a range suitable for storage.
  #
  # root           - A root Element from which to anchor the serialisation.
  # ignoreSelector - A selector String of elements to ignore. For example
  #                  elements injected by the annotator.
  #
  # Returns an instance of SerializedRange.
  serialize: (root, ignoreSelector) ->
    this.normalize(root).serialize(root, ignoreSelector)

  # Public: Returns the range as an Object literal.
  toObject: ->
    {
      start: @start
      startOffset: @startOffset
      end: @end
      endOffset: @endOffset
    }


# Export Range object.
module.exports = Range
