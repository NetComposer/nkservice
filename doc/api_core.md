# NkMEDIA Management API - Core API

In this chapter the core NkMEDIA API is described. This API is available even with no plugin or backend active.

## Login

The first thing you must do after connecting to the websocket interface is to log in. You must select a started service to log in into. NkMEDIA includes a default core service named 'nkmedia_core'. You can use it to start new services where you can perform real media processing.

For login, the corresponding `cmd` field is `login`, and the `data` field must include the following fields:


Field|Description
---|----
service|Service to connect to (for example, "nkmedia_core")
password|Configured password for the service

Example:

```json
{
	class: "nkmedia",
	cmd: "login",
	data: { service: "nkmedia_core", password: "mypass" }
	tid: 1
}
```

```json
{
	result: "ok",
	tid: 1
}
```


## Create a service


## Create a session

The key objects in NkMEDIA are sessions. You can start and manage any number of sessions. 

For session creation, the corresponding `cmd` field is `create_session`, and the `data` field can include the following fields (all of them are optional):

Field|Default|Description
---|----
wait_timeout|60|Changes default timeout for inactive sessions (secs)
ready_timeout|86400|Changes default timeout for active sessions (secs)
ring_timeout|30|Changes default timeout for ringing sessions (secs)
hangup_after_error|true|Forces hangup after an error in the session (boolean)

If the creation is successful, you will receive a session id.

Example:
```json
{
	class: "nkmedia",
	cmd: "create_session",
	data: { wait_timeout: 30 }
	tid: 2
}
```

```json
{
	result: "ok",
	data: { session_id: "b0f0c196-3541-5b9e-645f-38c9862f00d9"}
	tid: 2
}
```

Once you create a session, it enters into _wait_ state. You must supply an _offer operation_ and an _answer operation_. When the session stops, an event will be generated.


## Set session's offer operation

Once you have a session, you can set its _offer operation_. You can set as the offer for the session a raw _sdp_ (_webrtc_ or _sip_ compatible) or an operation than generates or transforms an offer you provide.

Without any plugin, the only offer operation allowed is setting an _sdp_. You could have got this sdp from the browser itself or one of the provided signaling plugins (like SIP or Verto).

The corresponding `cmd` field is `session_offer`, and the `data` field must include the following fields:

```json
{
	op: "sdp",
	offer: {
		sdp: "v=0....",
		sdp_type: "webrtc",
		type: "offer"
		...
	}
}
```








## Events

You can subscribe to any number of events related to the service you have logged in. You must select the `class` of events you want to be subscribed to, and, optionally, `subclass` of events, to further limit the type of events you are interested in. Once subscribed, you will start receiving all related events belonging to your service.

If you logged in to the core service (`nkmedia_core`), you will receive the event classes you subscribe to but beloging to _all_ services.

NkMEDIA Core supports the following events:

Class|SubClass|Event|Body|Description
---|---|---|---|---



