# NkSERVICE External API

## Introduction

Each started service can decide to publish an External API interface that can be deployed over TCP, TLS, WS or WSS connections. The service can use it for any of two very different use cases:

* For _server-side_ applications, to connect to the service and administer it, like starting and stopping it, update configuration, receiving events and subscribing to callbacks, so that you are notified and can authorize or not when an user logins, process incoming  calls, etc.
* As a way to connect _client-side_ applications (like browsers) to your service. NkSERVICE supports hundreds of thousands of external clients on a single box. The clients can use the methods and events that you decide to offer in your service configuration.

Currently, all messages over the external API interface are JSON messages. In the future other encoding mechanisms may be supported.

Any side of the connection (client or server) can send _requests_ to the other side, that must _answer_ them. All **requests** have the following fields:


Field|Sample|Comment
---|---|---
class|"core"|Subsystem or plugin responsible to process this message, at the server or the client. At the server, `core` class is managed by NkSERVICE itself. Any attached _plugin_ can support other classes.
cmd|"login"|Command to invoke at the client or the server, related to the class. 
data|{}|Optional information to add to the request.
tid|1|Each request must have an unique transaction id (any numerical or text value).

All messages must be answered immediately with a **response** having the following fields:

Field|Sample|Comment
---|---|---
result|"ok"|Each request class and command expects a set of specific answers. See bellow.
data|{}|Optional information to add to the response.
tid|1|Must match the `tid` field in the request

By convention, success responses will have `"result": "ok"`. Error responses will follow the following structure:

```js
{
	"result": "error",
	"data": {
		"error": "Error Description",
		"code": 1001	
	}
}
```

Responses are expected to be sent **immediately**. If a response is not going to be available within a sub-second time, the called party must send an **ack**, with the following structure:

```js
{
	"ack": 1	// Must match the tid of the request
}
```

NkSERVICE will close the connection if no response is received within 5 seconds. Sending each _ack_ will extend this timeout for 3 more minutes. NkSERVICE server will send periodic ping requests, that follow the same rule.


## Login

Right after starting the connection, the client must send a _login_ request (see [core commands](doc/api_commands.md)). The service or plugin responsible to accept the user must supply an `user` (a single user can start multiple connections) and an unique, session-specific `session_id`. The server provides a unique session_id, but the service login can change it, possibly during a session recovery procedure.

If you login to the External API server started by the core class (defined in NkSERVICE global configuration) you can only use the (also defined in the config) system-wide administrator's user and pass. In this case, you are allowed to perform administrative functions like creating new services (other ways to create services are defined in the introduction).

If you login to a server started by any other service, that service must attend the login petition, in its server logic (using Luerl or Erlang) or subscribing to the callback `api_server_login` (see bellow).


## Creating a service

To be able to create a service externally, the `core` service must be started and listening for incoming requests. You must connect to it and authenticate yourself using global administrator's credentials (see the previous point).

See the `create_service` command in (see [core commands](doc/api_commands.md)).


## Events

There is an special type of request called **event**. An event is identical to any other request, but the `cmd` field is `"event"`. All defined classes (included `core`) must support events. Events must be answered immediately, with `"result": "ok"` and no `data` field, since no response data is expected.

All received events have the following fields in the `data` field of the request:

Field|Sample|Comment
---|---|---
class|"media"|Class sending the event (client or server)
type|"stop"|Event type. Each class supports set of _event types_
obj|"session"|Object class or subsystem belonging to the class sending the event.
obj_id|"5179b729-367c-e79c-0399-38c9862f00d9"|Specific instance of the object class this event refers to.
service|"myservice"|Optionally, if the event is sent from a different service, the sending service is included.


### Subscriptions

Clients connecting to an external API server published by an specific service can subscribe to receive specific events. 

The core system and any attached plugin can send several types of events. All clients subscribed to the _class_, _type_, _obj_ and _obj_id_ of the event will receive it. Clients can also subscribe to groups of events using a wildcard definition, for example:

```js
{
	"class": "core",
	"cmd": "subscribe",
	"data": {
		"class": "media",
		"obj": "session",
		"obj_id": "*",
		"type": "*"
	}
}
```

In this example, this connection will subscribe to all events sent by the _media_ subsystem (provided by the [nkmedia](https://github.com/NetComposer/nkmedia) plugin), receiving all types of events (start, stop, etc.) generated by all sessions. 

See [core commands](doc/api_commands.md).


## Callbacks registrations

When using the external API as a way to manage its publishing service, you can subscribe not only to events, but also to callbacks generated at the server. 

The core system supports a number of callbacks, for example to allow registering users or to allow them to subscribe to specific events.

For example, you would use this request to be notified of incoming login requests and have the opportunity to authorize them:

```js
{
	"class": "core",
	"cmd": "register_callback",
	"data": {
		"class": "myservice",
		"callback": "login"
	},
	"tid": 1
}
```

after this is accepted by the server, next time an user tries to login you will receive a callback request:


```js
{
	"class": "core",
	"cmd": "api_server_login",
	"data": {
		"user": "my_user",
		"pass": "my_pass"
	},
	"tid": 101
}
```

and you could return:


```js
{
	"result": "ok",
	"data": {
		"authorized": "false",
		"reason": "Invalid password"
	},
	"tid": 101
}
```





