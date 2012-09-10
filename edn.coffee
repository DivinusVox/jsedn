us = require "underscore"

class Prim
	constructor: (val) ->
		if us.isArray val
			@val = us.filter val, (x) -> not (x instanceof Discard)
		else
			@val = val
			
	value: -> @val
	toString: -> JSON.stringify @val
	
class StringObj extends Prim 
	toString: -> @val
	is: (test) -> @val is test
	
class Tag
	constructor: (@namespace, @name...) ->
		if arguments.length is 1
			[@namespace, @name...] = arguments[0].split('/')
			
	ns: -> @namespace
	dn: -> [@namespace].concat(@name).join('/')
	
class Tagged extends Prim
	constructor: (@_tag, @_obj) ->

	ednEncode: ->
		"\##{@tag().dn()} #{encode @obj()}"

	tag: -> @_tag
	obj: -> @_obj

class Discard

class Iterable extends Prim
	ednEncode: ->
		(@map (i) -> encode i).join " "
	
	jsonEncode: ->
		(@map (i) -> if i.jsonEncode? then i.jsonEncode() else i)

	exists: (index) ->
		@val[index]?

	at: (index) ->
		if @exists index then @val[index]

methods = [
	'forEach', 'each', 'map', 'reduce', 'reduceRight', 'find'
	'detect', 'filter', 'select', 'reject', 'every', 'all', 'some', 'any'
	'include', 'contains', 'invoke', 'max', 'min', 'sortBy', 'sortedIndex'
	'toArray', 'size', 'first', 'initial', 'rest', 'last', 'without', 'indexOf'
	'shuffle', 'lastIndexOf', 'isEmpty', 'groupBy'
]
	
for method in methods
	do (method) ->
		Iterable.prototype[method] = -> 
			us[method].apply us, [@val].concat(us.toArray arguments)

for method in ['concat', 'join', 'slice']
	do (method) ->
		Iterable.prototype[method] = ->
			Array.prototype[method].apply @val, arguments

class List extends Iterable
	ednEncode: ->
		"(#{super()})"

	jsonEncode: ->
		List: super()
		
class Vector extends Iterable
	ednEncode: ->
		"[#{super()}]"

	jsonEncode: ->
		Vector: super()
		
class Set extends Iterable
	ednEncode: ->
		"\#{#{super()}}"

	jsonEncode: ->
		Set: super()

	constructor: (val) ->
		super()
		@val = us.uniq val

		if not us.isEqual val, @val
			throw "set not distinct"

class Map
	ednEncode: ->
		"{#{(encode i for i in @value()).join " "}}"
	
	jsonEncode: -> 
		{Map: ((if i.jsonEncode? then i.jsonEncode() else i) for i in @value())}

	constructor: (@val) ->
		@keys = []
		@vals = []
		
		for v, i in @val
			if i % 2 is 0
				@keys.push v
			else
				@vals.push v

		@val = false
	
	value: -> 
		result = []
		for v, i in @keys
			result.push v
			if @vals[i]? then result.push @vals[i]
		result
		
	exists: (key) ->
		for k, i in @keys
			if us.isEqual k, key
				return i
				
		return undefined
		
	at: (key) ->
		if (id = @exists key)?
			@vals[id]
		else
			throw "key does not exist"

	set: (key, val) ->
		if (id = @exists key)?
			@vals[id] = val
		else
			@keys.push key
			@vals.push val
			
		this

#based on the work of martin keefe: http://martinkeefe.com/dcpl/sexp_lib.html
parens = '()[]{}'
specialChars = parens + ' \t\n\r,'

parenTypes = 
	'(' : closing: ')', class: List
	'[' : closing: ']', class: Vector
	'{' : closing: '}', class: Map

lex = (string) ->
	list = []
	token = ''
	for c in string
		if not in_string? and c is ";"
			in_comment = true
			
		if in_comment
			if c is "\n"
				in_comment = undefined
				if token 
					list.push token
					token = ''
			continue
			
		if c is '"'
			if in_string?
				list.push (new StringObj in_string)
				in_string = undefined
			else
				in_string = ''
			continue

		if in_string?
			in_string += c
		else if c in specialChars
			if token
				list.push token
				token = ''
			if c in parens
				list.push c
		else
			if token is "#_"
				list.push token
				token = ''			
			token += c

				
	if token
		list.push(token)
	list

#based roughly on the work of norvig from his lisp in python
read = (tokens) ->
	read_ahead = (token) ->
		if token is undefined then return

		if paren = parenTypes[token]
			closeParen = paren.closing
			L = []
			while true
				token = tokens.shift()
				if token is undefined then throw 'unexpected end of list'

				if token is paren.closing then return (new paren.class L) else L.push read_ahead token

		else if token in ")]}" then throw "unexpected #{token}"

		else
			handledToken = handle token
			if handledToken instanceof Tag
				token = tokens.shift()
				if token is undefined then throw 'was expecting something to follow a tag'
				tagged = new Tagged handledToken, read_ahead token
				if tagged.tag().dn() is ""
					if tagged.obj() instanceof Map
						return new Set tagged.obj().value()
				
				if tagged.tag().dn() is "_"
					return new Discard
				
				if tagActions[tagged.tag().dn()]?
					return tagActions[tagged.tag().dn()].action tagged.obj()
				
				return tagged
			else
				return handledToken

	token1 = tokens.shift()
	if token1 is undefined
		return undefined 
	else
		result = read_ahead token1
		if result instanceof Discard 
			return ""
		return result

handle = (token) ->
	if token instanceof StringObj
		return token.toString()
		
	for name, handler of tokenHandlers
		if handler.pattern.test token
			return handler.action token
	token

tokenHandlers =
	nil:       pattern: /^nil$/,               action: (token) -> null
	boolean:   pattern: /^true$|^false$/,      action: (token) -> token is "true"
	character: pattern: /^\\[A-z0-9]$/,        action: (token) -> token[-1..-1]
	tab:       pattern: /^\\tab$/,             action: (token) -> "\t"
	newLine:   pattern: /^\\newline$/,         action: (token) -> "\n"
	space:     pattern: /^\\space$/,           action: (token) -> " "
	keyword:   pattern: /^\:.*$/,              action: (token) -> token[1..-1]
	integer:   pattern: /^\-?[0-9]*$/,         action: (token) -> parseInt token
	float:     pattern: /^\-?[0-9]*\.[0-9]*$/, action: (token) -> parseFloat token
	tagged:    pattern: /^#.*$/,               action: (token) -> new Tag token[1..-1]

tagActions = 
		uuid: tag: (new Tag "uuid"), action: (obj) -> obj
		inst: tag: (new Tag "inst"), action: (obj) -> obj

#ENCODING
isKeyword = (str) ->
	(" " not in str) and (tokenHandlers.keyword.pattern.test str)
		
encode = (obj, prim = true) ->
	if obj.ednEncode?
		obj.ednEncode()

	else if us.isArray obj
		result = []
		for v in obj
			result.push encode v, prim
		"(#{result.join " "})"
			
	else if tokenHandlers.integer.pattern.test "#{obj}"
		parseInt obj

	else if tokenHandlers.float.pattern.test "#{obj}"
		parseFloat obj

	else if us.isString obj
	
		if prim and isKeyword ":#{obj}"
			":#{obj}"
		else
			"\"#{obj.toString()}\""

	else if us.isBoolean obj
		if obj 
			"true"
		else
			"false"

	else if us.isNull obj
		"nil"

	else if us.isObject
		result = []
		for k, v of obj
			result.push encode k, true
			result.push encode v, true
		"{#{result.join " "}}"

encodeJson = (obj) ->
	if obj.jsonEncode?
		return encodeJson obj.jsonEncode()

	JSON.stringify obj
	
exports.List = List
exports.Vector = Vector
exports.Map = Map
exports.Set = Set
exports.Tag = Tag
exports.Tagged = Tagged
exports.setTagAction = (tag, action) -> tagActions[tag.dn()] = tag: tag, action: action
exports.setTokenPattern = (handler, pattern) -> tokenHandlers[handler].pattern = pattern
exports.setTokenAction = (handler, action) -> tokenHandlers[handler].action = action
exports.parse = (string) -> read lex string
exports.encode = encode
exports.encodeJson = encodeJson