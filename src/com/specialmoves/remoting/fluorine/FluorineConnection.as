/*
 * Licensed under the MIT License
 * 
 * Copyright (c) 2010 Specialmoves Ltd
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 * 
 * http://github.com/specialmoves/FluorineConnection
 * http://www.opensource.org/licenses/mit-license.php
 */
package com.specialmoves.remoting.fluorine {
	import flash.events.EventDispatcher;
	import flash.events.NetStatusEvent;
	import flash.net.NetConnection;
	import flash.net.ObjectEncoding;
	import flash.net.Responder;

	/**
	 * This class handles creating a connection to the Fluorine gateway and is the object which all calls to the gateway must be made through.
	 * 
	 * @author mattbilson 22 Jan 2010
	 * @version 3.0 
	 * @see com.specialmoves.remoting.fluorine.IFluorineConfig 
	 * 
	 * @example The following code shows the functionality of FluorineConnection
	 * <listing version="3.0"> 
		 * //set up fluorine connection (PureMVC projects can do this in PrepModelCommand)
		 * var config : IFluorineConfig = new FluorineConfig("domain" + "/Gateway.aspx");
		 * var standardFluorineConnection : IFluorineConnection = new FluorineConnection(config);
		 * //you can listen for errors on the connection object
		 * standardFluorineConnection.addEventListener(FluorineErrorEvent.CONNECT_ERROR, errorHandler, false, 0, true);
		 * standardFluorineConnection.addEventListener(FluorineErrorEvent.CALL_ERROR, errorHandler, false, 0, true);
			
		 * //you can set up more than one connection. To use different domains, or totally different configurations.
		 * var noCdnFluorineConnection : IFluorineConnection = new FluorineConnection(new FluorineConfig("noCdnDomain" + "/Gateway.aspx"));
		 * 	
		 * //PureMVC projects can pass the relevant connection to the proxies which need it
		 * facade.registerProxy(new ContentProxy(standardFluorineConnection));
		 * 	
		 * //Make a call
		 * var responder : Responder = new Responder(onSuccess, onError);
		 * var contentId : String = "1";
		 * standardFluorineConnection.call("Content.GetTypedContentByVirtualPathID", responder, contentId);
		 * 
		 * //during development, there's a utility error handler you can use for quick debugging
		 * var responder : Responder = new Responder(onSuccess, FluorineUtils.onError);
		 * var contentId : String = "1";
		 * standardFluorineConnection.call("Content.GetTypedContentByVirtualPathID", responder, contentId);
	 * </listing>
	 * 
	 */
	public class FluorineConnection extends EventDispatcher implements IFluorineConnection {
		
		/**
		 * Dispatched when trying to connect throws an Error
		 * @eventType com.specialmoves.remoting.fluorine.FluorineErrorEvent.CONNECT_ERROR
		 */
		[Event(name="CONNECT_ERROR", type="com.specialmoves.remoting.fluorine.FluorineErrorEvent")]
		
		/**
		 * Dispatched when a NetStatus event with a level of error is heard.
		 * @eventType com.specialmoves.remoting.fluorine.FluorineErrorEvent.CALL_ERROR
		 */
		[Event(name="CALL_ERROR", type="com.specialmoves.remoting.fluorine.FluorineErrorEvent")]
		
		
		/**
		 * @private
		 */
		private var _connection : NetConnection;
		
		/**
		 * @private
		 */
		private var _connected : Boolean;
		
		/**
		 * @private
		 */
		private var _addApiPrefix : Boolean;

		/**
		 * the NetConnection managed by this FluorineConnection
		 * @default = null
		 */
		private function get connection() : NetConnection {
			return _connection;
		}
		
		/**
		 * @private
		 */
		private var _config : IFluorineConfig;
		
		/**
		 * @see com.specialmoves.remoting.fluorine.IFluorineConfig.
		 * @param value The object containing all the configuration data for this connection
		 */
		private function set config(value : IFluorineConfig) : void {
			_config = value;
			configure();
		}
		
		/**
		 * A FluorineConnection can't be created without a certain amount of configuration data, so an IFluorineConfig instance needs
		 * to be passed in to the constructor.
		 * 
		 * @see com.specialmoves.remoting.fluorine.IFluorineConfig.
		 * @param config The object containing all the configuration data for this connection
		 */
		public function FluorineConnection(config : IFluorineConfig) {
			super();
			this.config = config;
			_addApiPrefix = false; // dot not add prefix by design
		}
		
		/**
		 * This is called after the connection has it's config set.
		 * @see config
		 */
		private function configure() : void {
			_config.defineClassMapping();
		}
		
		/**
		 * Turn on/off the API prefix appender.
		 * @param value The object containing all the configuration data for this connection
		 */
		public function addApiPrefix(addPrefix:Boolean) : void {
			_addApiPrefix = addPrefix;
		}
		
		/**
		 * This function creates the Fluorine connection to the gateway at IFluorineConfig.gatewayURL
		 * @private
		 * @see com.specialmoves.remoting.fluorine.IFluorineConfig#gatewayURL
		 */
		public function connect() : void {			
			_connection = new NetConnection();
			_connection.objectEncoding = ObjectEncoding.AMF3;
			// the following indicates the object on which callback methods are invoked.
			// it is required otherwhise function 'RequestPersistentHeader' is not found and the following error is thrown:
			// Error #2044: Unhandled AsyncErrorEvent:. text=Error #2095: flash.net.NetConnection was unable to invoke callback RequestPersistentHeader.
			_connection.client = this;
			_connection.addEventListener(NetStatusEvent.NET_STATUS, onNetStatusHandler);
			
			try {
				//will this connect instantly? seems to be no way of detecting if it's connected
				//it doesn't dispatch a connected netstatus event, and the .connected property only concerns RTMP not HTTP.
				_connection.connect(_config.gatewayURL);
				_connected = true;
			} catch (e:Error) {
				dispatchEvent(new FluorineErrorEvent(FluorineErrorEvent.CONNECT_ERROR,false, false, "Unable to connect to Fluorine (" + _config.gatewayURL + ")"));
			}
		}
		
		/**
		 * This is how to make a call to the Fluorine backend.
		 *  
		 * @param command The name of the method to call
		 * @param responder The responder which will listen for the typed success/error responses 
		 * @param rest The parameters which will be passed to the method 
		 */
		public function call(command:String,responder : Responder, ...rest):void {
			if(!_connected) connect();
			if(_addApiPrefix) command = _config.apiPrefix + command;
			log("Fluorine call : " + command + "(" + rest + ")");
			connection.call.apply(connection,[command,responder].concat(rest));
		}

		/**
		 * This handles any NetStatusEvent.NET_STATUS event dispatched
		 * by <code>connection</code>.
		 * 
		 * @param e The NetStatusEvent dispatched.
		 */
		private function onNetStatusHandler(e : NetStatusEvent) : void {
			var msg:String = e.info['code'];
			switch(e.info['level']) {
				case "error" :
					dispatchEvent(new FluorineErrorEvent(FluorineErrorEvent.CALL_ERROR,false,false, msg + " (url:" + _config.gatewayURL +", description : '"+e.info.description+"')"));
					break;
				case "status" :
					log(msg);
				break;
				case "warning" :
					log(msg);
					break;
				default :
					log(e.info['level'] + " : " + msg);
			}
		}
		
		/**
		 * Just a utility function to trace out any information
		 * Feel free to replace the use of trace() with your favourite logging system.
		 */
		private function log(message : String) : void {
			trace(message);
		}
		
		/**
		 * Gets called by the server to set the client's ID.
		 * If not implemented, an error is thrown (at least using Flash Adobe CS5) .
		 * @param DSIdInfo contains a name, a mustUnderstand flag, and a DSID (Data Set Identification)
		 */
		public function RequestPersistentHeader(DSIdInfo:Object):void
		{
			/*var header:String = "";
			for(var prop:String in DSIdInfo) {
				header = header.concat(" ", DSIdInfo[prop]);
			}
			log("Persistent header is received:" + header);*/
		}
	}
}
