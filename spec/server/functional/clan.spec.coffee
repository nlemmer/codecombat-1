Clan = require '../../../server/models/Clan'
AnalyticsLogEvent = require '../../../server/models/AnalyticsLogEvent'
User = require '../../../server/models/User'
request = require '../request'
utils = require '../utils'


describe 'POST /db/clan', ->
  url = utils.getUrl('/db/clan')
  
  it 'returns 401 for anonymous users', utils.wrap ->
    yield utils.logout()
    json =
      type: 'public'
      name: _.uniqueId('myclan')
    [res] = yield request.postAsync  { url, json }
    expect(res.statusCode).toBe(401)
    
  it 'returns 422 unless type and name are present', utils.wrap ->
    user = yield utils.initUser()
    yield utils.loginUser(user)
    json =
      name: _.uniqueId('myclan')
    [res] = yield request.postAsync { url, json }
    expect(res.statusCode).toBe(422)

    json =
      type: 'public'
    [res] = yield request.postAsync { url, json }
    expect(res.statusCode).toBe(422)
    
  it 'returns 402 if you are not subscribed AND type is private', utils.wrap ->
    user = yield utils.initUser()
    yield utils.loginUser(user)
    json =
      name: _.uniqueId('myclan')
      type: 'private'
    [res] = yield request.postAsync { url, json }
    expect(res.statusCode).toBe(403)

    user = yield utils.initUser({stripe: {free: true}})
    yield utils.loginUser(user)
    [res] = yield request.postAsync { url, json }
    expect(res.statusCode).toBe(200)



  it 'accepts description, and adds the creator to the list of members', utils.wrap ->
    user = yield utils.initUser()
    yield utils.loginUser(user)
    json =
      name: _.uniqueId('myclan')
      type: 'public'
      description: 'A description'
    [res] = yield request.postAsync { url, json }
    expect(res.statusCode).toBe(200)
    clan = yield Clan.findById(res.body._id)
    expect(clan.get('type')).toEqual(json.type)
    expect(clan.get('name')).toEqual(json.name)
    expect(clan.get('description')).toEqual(json.description)
    expect(clan.get('members').length).toEqual(1)
    expect(clan.get('members')[0]).toEqual(user._id)
    user = yield User.findById(user)
    expect(user.get('clans').length).toBe(1)
    expect(user.get('clans')[0].equals(clan._id)).toBe(true)

    
describe 'PUT /db/clan', ->
  url = utils.getUrl('/db/clan')
  
  it 'allows owners to edit the clan name and description', utils.wrap ->
    user = yield utils.initUser({stripe: {free: true}})
    yield utils.loginUser(user)
    clan = yield utils.makeClan({type: 'public'})
    json = clan.toObject()
    json.name = 'new name' + _.uniqueId()
    json.description = 'new description'
    [res] = yield request.putAsync { url , json }
    expect(res.body.name).toEqual(json.name)
    expect(res.body.description).toEqual(json.description)
    clan = yield Clan.findById(clan.id)
    expect(clan.get('name')).toEqual(json.name)
    expect(clan.get('description')).toEqual(json.description)
    
    user2 = yield utils.initUser()
    yield utils.loginUser(user2)
    [res] = yield request.putAsync { url , json }
    expect(res.statusCode).toBe(403)
    
    
describe 'GET /db/clan/:handle', ->
  it 'returns private clans, even when anonymous', utils.wrap ->
    user = yield utils.initUser({stripe: {free: true}})
    yield utils.loginUser(user)
    privateClan = yield utils.makeClan({type: 'private'})
    
    url = utils.getUrl("/db/clan/#{privateClan.id}")
    otherUser = yield utils.initUser()
    yield utils.loginUser(otherUser)
    [res] = yield request.getAsync({url, json: true})
    expect(res.statusCode).toBe(200)
    expect(res.body._id).toEqual(privateClan.id)
    
    yield utils.becomeAnonymous()
    [res] = yield request.getAsync({url, json: true})
    expect(res.statusCode).toBe(200)

    
describe 'GET /db/clan/-/public', ->
  url = utils.getUrl('/db/clan/-/public')
  
  beforeEach utils.wrap ->
    yield utils.clearModels([Clan])
    
  it 'returns all public clans, even for anonymous players', utils.wrap ->
    user = yield utils.initUser({stripe: {free: true}})
    yield utils.loginUser(user)
    yield utils.makeClan({type: 'public'})
    publicClan = yield utils.makeClan({type: 'public'})
    privateClan = yield utils.makeClan({type: 'private'})
    [res] = yield request.getAsync { url, json: true }
    expect(res.statusCode).toBe(200)
    expect(res.body.length).toBe(2)
    expect(_.find(res.body, {_id: publicClan.id})).toBeTruthy()
    expect(_.find(res.body, {_id: privateClan.id})).toBeFalsy()
    
    yield utils.becomeAnonymous()
    [res] = yield request.getAsync { url, json: true }
    expect(res.statusCode).toBe(200)

    
describe 'PUT /db/clan/-/join', ->
  beforeEach utils.wrap ->
    @user = yield utils.initUser({stripe: {free: true}})
    yield utils.loginUser(@user)
    @clan = yield utils.makeClan({type: 'public'})
    @url = utils.getUrl("/db/clan/#{@clan.id}/join")
    @privateClan = yield utils.makeClan({type: 'private'})
    @privateUrl = utils.getUrl("/db/clan/#{@privateClan.id}/join")

  it 'joins the clan idempotently', utils.wrap ->
    user = yield utils.initUser()
    yield utils.loginUser(user)
    [res] = yield request.putAsync { @url, json: true }
    expect(res.statusCode).toBe(200)
    clan = yield Clan.findById @clan.id
    expect(clan.get('members').length).toEqual(2)
    expect(_.find clan.get('members'), (memberID) -> user._id.equals memberID).toBeDefined()
    user = yield User.findById user.id
    expect(user.get('clans')?.length).toBe(1)
    expect(_.find user.get('clans'), (clanID) -> clan._id.equals clanID).toBeDefined()

    [res] = yield request.putAsync { @url, json: true }
    expect(res.statusCode).toBe(200)
    clan = yield Clan.findById @clan.id
    expect(clan.get('members').length).toEqual(2)
    user = yield User.findById user.id
    expect(user.get('clans')?.length).toBe(1)
    

  it 'returns 404 if the clan DNE', utils.wrap ->
    user = yield utils.initUser()
    yield utils.loginUser(user)
    url = utils.getUrl('/db/clan/1234/join')
    [res] = yield request.putAsync { url, json: true }
    expect(res.statusCode).toBe(404)

  it 'returns 401 for anonymous users', utils.wrap ->
    yield utils.logout()
    [res] = yield request.putAsync { @url, json: true }
    expect(res.statusCode).toBe(401)

  it 'returns 403 if the clan is private and user is not premium', utils.wrap ->
    yield @clan.update({$set: {type: 'public'}})
    user = yield utils.initUser()
    yield utils.loginUser(user)
    [res] = yield request.putAsync { url: @privateUrl, json: true }
    expect(res.statusCode).toBe(403)
    yield user.update({$set: {stripe: {free: true}}})
    [res] = yield request.putAsync { url: @privateUrl, json: true }
    expect(res.statusCode).toBe(200)

    
    
describe 'PUT /db/clan/:handle/leave', ->

  beforeEach utils.wrap ->
    @ownerUser = yield utils.initUser()
    yield utils.loginUser(@ownerUser)
    @clan = yield utils.makeClan({type: 'public'})
    @url = utils.getUrl("/db/clan/#{@clan.id}/join")
    @joinerUser = yield utils.initUser()
    yield utils.loginUser(@joinerUser)
    url = utils.getUrl("/db/clan/#{@clan.id}/join")
    [res] = yield request.putAsync { url, json: true }
    expect(res.statusCode).toBe(200)
    @clan = yield Clan.findById(@clan.id)
    @ownerUser = yield User.findById(@ownerUser.id)
    @joinerUser = yield User.findById(@joinerUser.id)
    expect(@clan.get('members').length).toBe(2)
    expect(@ownerUser.get('clans').length).toBe(1)
    expect(@joinerUser.get('clans').length).toBe(1)
    @url = utils.getUrl("/db/clan/#{@clan.id}/leave")

  it 'leaves the clan, unless you are the creator', utils.wrap ->
    yield utils.loginUser(@joinerUser)
    [res] = yield request.putAsync { @url, json: true }
    expect(res.statusCode).toBe(200)
    
    @clan = yield Clan.findById(@clan.id)
    @ownerUser = yield User.findById(@ownerUser.id)
    @joinerUser = yield utils.initUser()
    expect(@clan.get('members').length).toBe(1)
    expect(@clan.get('members')[0].equals(@ownerUser._id)).toBe(true)
    expect(@ownerUser.get('clans').length).toBe(1)
    expect(@joinerUser.get('clans')).toBeUndefined()

    yield utils.loginUser(@ownerUser)
    [res] = yield request.putAsync { @url, json: true }
    expect(res.statusCode).toBe(403)
    

describe 'PUT /db/clan/:clanHandle/remove/:memberHandle', ->

  beforeEach utils.wrap ->
    @ownerUser = yield utils.initUser()
    yield utils.loginUser(@ownerUser)
    @clan = yield utils.makeClan({type: 'public'})
    @url = utils.getUrl("/db/clan/#{@clan.id}/join")
    @joinerUser = yield utils.initUser()
    yield utils.loginUser(@joinerUser)
    url = utils.getUrl("/db/clan/#{@clan.id}/join")
    [res] = yield request.putAsync { url, json: true }
    expect(res.statusCode).toBe(200)
    @clan = yield Clan.findById(@clan.id)
    @ownerUser = yield User.findById(@ownerUser.id)
    @joinerUser = yield User.findById(@joinerUser.id)
    expect(@clan.get('members').length).toBe(2)
    expect(@ownerUser.get('clans').length).toBe(1)
    expect(@joinerUser.get('clans').length).toBe(1)
    

  it 'removes members idempotently', utils.wrap ->
    yield utils.loginUser(@ownerUser)
    url = utils.getUrl("/db/clan/#{@clan.id}/remove/#{@joinerUser.id}")
    [res] = yield request.putAsync { url, json: true }
    expect(res.statusCode).toBe(200)
    clan = yield Clan.findById @clan.id
    expect(clan.get('members').length).toEqual(1)
    expect(clan.get('members')[0]).toEqual(@ownerUser._id)
    joinerUser = yield User.findById @joinerUser.id
    expect(joinerUser.get('clans').length).toEqual(0)

    [res] = yield request.putAsync { url, json: true }
    expect(res.statusCode).toBe(200)
    clan = yield Clan.findById @clan.id
    expect(clan.get('members').length).toEqual(1)


  it 'returns 404 if the member or clan DNE', utils.wrap ->
    url = utils.getUrl("/db/clan/1234/remove/#{@joinerUser.id}")
    [res] = yield request.putAsync { url, json: true }
    expect(res.statusCode).toBe(404)

    url = utils.getUrl("/db/clan/#{@clan.id}/remove/1234")
    [res] = yield request.putAsync { url, json: true }
    expect(res.statusCode).toBe(404)

  it 'returns 403 if you are not the owner, or the owner tries to remove themself', utils.wrap ->
    forbiddenUser = yield utils.initUser()
    url = utils.getUrl("/db/clan/#{@clan.id}/remove/#{@joinerUser.id}")
    [res] = yield request.putAsync { url, json: true }
    expect(res.statusCode).toBe(403)

    # try joining first
    url = utils.getUrl("/db/clan/#{@clan.id}/join")
    [res] = yield request.putAsync { url, json: true }
    expect(res.statusCode).toBe(200)

    # still forbidden!
    url = utils.getUrl("/db/clan/#{@clan.id}/remove/#{@joinerUser.id}")
    [res] = yield request.putAsync { url, json: true }
    expect(res.statusCode).toBe(403)

    # owner cannot remove owner
    yield utils.loginUser(@ownerUser)
    url = utils.getUrl("/db/clan/#{@clan.id}/remove/#{@ownerUser.id}")
    [res] = yield request.putAsync { url, json: true }
    expect(res.statusCode).toBe(403)


fdescribe 'DELETE /db/clan/:handle', ->

  beforeEach utils.wrap ->
    @ownerUser = yield utils.initUser()
    yield utils.loginUser(@ownerUser)
    @clan = yield utils.makeClan({type: 'public'})
    @url = utils.getUrl("/db/clan/#{@clan.id}/join")
    @joinerUser = yield utils.initUser()
    yield utils.loginUser(@joinerUser)
    url = utils.getUrl("/db/clan/#{@clan.id}/join")
    [res] = yield request.putAsync { url, json: true }
    expect(res.statusCode).toBe(200)
    @clan = yield Clan.findById(@clan.id)
    @ownerUser = yield User.findById(@ownerUser.id)
    @joinerUser = yield User.findById(@joinerUser.id)
    expect(@clan.get('members').length).toBe(2)
    expect(@ownerUser.get('clans').length).toBe(1)
    expect(@joinerUser.get('clans').length).toBe(1)
    @url = utils.getUrl("/db/clan/#{@clan.id}")
    yield utils.clearModels([AnalyticsLogEvent])

  it 'deletes the clan and logs an event', utils.wrap ->
    yield utils.loginUser(@ownerUser)
    [res] = yield request.delAsync { @url, json: true }
    expect(res.statusCode).toBe(204)
    @ownerUser = yield User.findById(@ownerUser.id)
    @joinerUser = yield User.findById(@joinerUser.id)
    expect(@ownerUser.get('clans').length).toBe(0)
    expect(@joinerUser.get('clans').length).toBe(0)
    events = yield AnalyticsLogEvent.find()
    expect(events.length).toBe(1)
    expect(events[0].get('properties.clanID')).toBe(@clan.id)
    expect(events[0].get('properties.type')).toBe(@clan.get('type'))

  it 'returns 401 if anonymous', utils.wrap ->
    yield utils.logout()
    [res] = yield request.delAsync { @url, json: true }
    expect(res.statusCode).toBe(401)

  it 'returns 403 if you are not the owner', utils.wrap ->
    yield utils.loginUser(@joinerUser)
    [res] = yield request.delAsync { @url, json: true }
    expect(res.statusCode).toBe(403)

  it 'returns 404 if the clan was already deleted, or is an invalid url', utils.wrap ->
    yield utils.loginUser(@ownerUser)
    [res] = yield request.delAsync { @url, json: true }
    expect(res.statusCode).toBe(204)

    [res] = yield request.delAsync { @url, json: true }
    expect(res.statusCode).toBe(404)

    url = utils.getUrl("/db/clan/1234")
    [res] = yield request.delAsync { url, json: true }
    expect(res.statusCode).toBe(404)

