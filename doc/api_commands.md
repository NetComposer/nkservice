# NkSERVICE External API

Class|Subclass|Cmd|Description
---|---|---|---
`core`|`user`|[`login`](#login)|Log in
`core`|`user`|[`list`](#list-users)|List current logged in users
`core`|`user`|[`get`](#get-user-info)|Get info about an user
`core`|`user`|[`send_event`](#send-an-event-to-an-user)|Sends a event to an user
`core`|`session`|[`stop`](#disconnect-a-session)|Forces disconnection of a sessions
`core`|`session`|[`send_event`](#send-an-event-to-a-session)|Sends a event to a session
`core`|`session`|[`cmd`](#send-a-command-to-a-session)|Sends a command to a session
`core`|`event`|[`subscribe`](#subscribe)|Subscribe to events
`core`|`event`|[`unsubscribe`](#unsubscribe)|Remove a previously registered subscription
`core`|`event`|[`get_subscriptions`](#get-subscriptions)|Get all current subscriptions
`core`|`event`|[`send_event`](#send-event)|Fires an event


The currently supported External API commands as described here. See [External API](api_intro.md) for an introduction to the External API. See the documentation of each plugin to learn the supported classes and commands.


## Login

Right after starting the connection, the client must send a _login_ request. You must supply an `user` and, optionally, a password. Any installed plugins may add other authentication mechanisms, or ways to extract metadata from the request.

The `user` can be any unique string, but an _email-like_ string is recommended. 

By default, the only recognized user is the one defined in the configuration (as _admin_) and it expects a `password` (_admin_password_).

Each connection has an unique `session_id`. If you don't supply one, it will be automatically generated. 


Field|Default|Description
---|---|---|---
user|(mandatory)|User who is logging in.
password|(mandatory for admin user)|Password
session_id|(automatic)|Session-id specific for this connection

**Sample**

```js
{
	class: "core",
	subclass: "user",
	cmd: "login",
	data: {
		user: "user@domain.com",
		password: "1234",
		meta1: "value1"
	},
	tid: 1
}
```
-->
```js
{
	result: "ok",
	data: {
		session_id: "54c1b637-36fb-70c2-8080-28f07603cda8"
	}
	tid: 1
}
```


## Send an event to an user

Allows a connection to send an event to all started sessions by an specific user.

Field|Default|Description
---|---|---|---
user|(mandatory)|User who is logging in.
type|`"*"`|Event type to send
body|`{}`|Body to include in the message



 (see [core commands](api_commands.md)). The service or plugin responsible to accept the user must supply an `user` (a single user can start multiple connections) and an unique, session-specific `session_id`. The server provides a unique session_id, but the service login can change it, possibly during a session recovery procedure.


## List Users

Returns a list of currently logged in users for the _service_, along with their started
sessions.

**Sample**

```js
{
	class: "core",
	subclass: "user",
	cmd: "list",
	tid: 1
}
```
-->
```js
{
	result: "ok",
	data: {
		"user1@domain.com": [
			"54c1b637-36fb-70c2-8080-28f07603cda8",
      		"ed26cbdb-36fb-70d7-fdcd-28f07603cda8"
    	],
		"user2@domain.com": [
      		"b840f878-36fb-70e1-f3df-28f07603cda8"
    	],    	
	}
	tid: 1
}
```


## Get User Info

Gets information about a logged in user. Returns a list of started sessions and metadata stored at the server. The server login can decide which information must be returned.

The field `user` is mandatory.

**Sample**


```js
{
	class: "core",
	subclass: "user",
	cmd: "get",
	data: {
		"user": "user1@domain.com"
	},
	tid: 1
}
```
-->
```js
{
	result: "ok",
	data: {
		"54c1b637-36fb-70c2-8080-28f07603cda8": {
			"remote": "wss:127.0.0.1:63393",
			"type": "api_server"
		},
		"ed26cbdb-36fb-70d7-fdcd-28f07603cda8": {
			"remote": "wss:127.0.0.1:63396",
			"type": "api_server"
    	},
	}
	tid: 1
}
```


## Send an event to an user

Allows a connection to send an event to all started sessions by an specific user.

Field|Default|Description
---|---|---|---
user|(mandatory)|User to send the event to
type|`"*"`|Event type to send
body|`{}`|Body to include in the message


**Sample**

```js
{
	class: "core",
	subclass: "user",
	cmd: "send_event",
	data: {
		user: "user2@domain.com",
		type: "my_type",
		body: {
			key: "val"
		}
	},
	tid: 1
}
```

The destination client will receive this message over all started sessions:

```js
{
	class: "core",
	cmd: "event",
	data: {
		class: "core",
		subclass: "user_event",
		type: "my_type",
		obj_id: "user2@domain.com"
	}
	tid: 1
}
```



## Disconnect a session

Disconnects a currently started session. The field `session_id` is mandatory.

**Sample**

```js
{
	class: "core",
	class: "session",
	cmd: "stop",
	data: {
		"session_id": "54c1b637-36fb-70c2-8080-28f07603cda8"
	},
	tid: 1
}
```



## Send an event to a session

Allows a connection to send an event to a specific session

Field|Default|Description
---|---|---|---
session_id|(mandatory)|Session to send the event to
type|`"*"`|Event type to send
body|`{}`|Body to include in the message


**Sample**

```js
{
	class: "core",
	class: "session",
	cmd: "send_event",
	data: {
		session_id: "275a94a7-36fb-8fce-1f4b-28f07603cda8",
	},
	tid: 1
}
```

The destination session will receive this message over all started sessions:

```js
{
	class: "core",
	cmd: "event",
	data: {
		class: "core",
		subclass: "session_event",
		obj_id: "275a94a7-36fb-8fce-1f4b-28f07603cda8"
	}
	tid: 1
}
```



## Send a command to a session

Allows to send a synchronous command a to a different session, and return the response.

Field|Default|Description
---|---|---|---
session_id|(mandatory)|Session to send the event to
class|(mandatory)|Class to include in the request
subclass|`"core"`|Subclass to include in the request
cmd|(mandatory)|Command to include in the request
data|`{}`|Optional data field


**Sample**

```js
{
	class: "core",
	class: "session",
	cmd: "cmd",
	data: {
		session_id: "275a94a7-36fb-8fce-1f4b-28f07603cda8",
		class: "my_class",
		cmd: "my_cmd",
		data: { 
			key: "val"
		}
	},
	tid: 1
}
```

The destination session will receive this request:

```js
{
	class: "my_class",
	cmd: "my_cmd",
	data: {
		key: "val",
	}
	tid: 1001
}
```

then, if the remote sessions answers:

```js
{
	result: "ok",
	data: {
		received: true,
	}
	tid: 1001
}
```

the calling session will receive as response:

```js
{
	result: "ok",
	data: {
		received: true,
	}
	tid: 1
}
```




## Subscribe

Allows the connection to subscribe to specific events or event classes. The only mandatory field is `class`. 

See each plugin documentation to learn the supported event subclasses and types of each supported class.

Field|Default|Description
---|---|---|---
class|(mandatory)|Class to subscribe to
subclass|`"*"`|Subscribe only to this subclass (`"*"` to subscribe to all)
type|`"*"`|Only to this event type (`"*"` to subscribe to all)
obj_id|`"*"`|Only to events generated by this specific object (`"*"` to all)
body|`{}`|Body to merge to incoming message's body
service|(this service)|Subscribe to events generated at a different _service_

The subscription attempt must be authorized by the server side code. If the connection is dropped, all subscriptions are deleted.

Fired events can have a body. If both the event's body and the subscription body are objects, they will be merged in the incoming event.

**Sample**

```js
{
	class: "core",
	subclass: "event",
	cmd: "subscribe",
	data: {
		class: "media",
		subclass: "session"
		body: {
			my_key: "my value"
		}
	}
	tid: 1
}
```

This example would subscribe the connection to all specific sessions and event types for sessions belonging to the `media` class. All events sent from class `media`, generated at object `session` (with any `type` and `obj_id`) will be sent to this connection.

Fields omitted or with value `"*"` will match all possible values for that field, including the case were the sender didn't use that field.


### Unsubscribe

Removes a previously registered subscription. Must match exactly the same fields used for the subscription (except `body`).


**Sample**

```js
{
	class: "core",
	subclass: "event",
	cmd: "unsubscribe",
	data: {
		class: "media",
		subclass: "session"
	},
	tid: 1
}
```


## Get subscriptions

Gets the current list of subscriptions for a session.
All sessions are subscribed automatically to receive user events and session events.

**Sample**

```js
{
	class: "core",
	subclass: "event",
	cmd: "get_subscriptions",
	tid: 1
}
```
-->
```js
{
	result: "ok",
	data: [
		{
			"class": "core",
       		"subclass": "session_event",
       		"obj_id": "275a94a7-36fb-8fce-1f4b-28f07603cda8",
       		"type": "*"
        },
     	{
     		"class": "core",
       		"subclass": "user_event",
       		"obj_id": "user1@domain.com",
       		"type": "*"
       	}
    ],
	tid: 1
}
```

## Send event

Allows to fire an event. 

Field|Default|Description
---|---|---|---
class|(mandatory)|Class to send the event to
subclass|`"*"`|Subclass to send the event to
type|`"*"`|Event type to send
obj_id|`"*"`|Specific object id
body|`{}`|Body to include in the message
service|(this service)|Send the event to a different _service_

Fields omitted or with value `"*"` will be omitted in the event. Only clients subscribed to the value `"*"` for that field (or that omitted them in the subscription request) will receive the message.


**Sample**

```js
{
	class: "core",
	subclass: "event",
	cmd: "send",
	data: {
		class: "my_class",
		subclass: "my_subclass"
		body: {
			my_key: "my value"
		}
	}
	tid: 1
}
```

