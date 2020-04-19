/*|--minAjax.js--|
  |--(A Minimalistic Pure JavaScript Header for Ajax POST/GET Request )--|
  |--Author : flouthoc (gunnerar7@gmail.com)(http://github.com/flouthoc)--|
  |--Contributers : Add Your Name Below--|
  */
function initXMLhttp() {

    var xmlhttp;
    if (window.XMLHttpRequest) {
        //code for IE7,firefox chrome and above
        xmlhttp = new XMLHttpRequest();
    } else {
        //code for Internet Explorer
        xmlhttp = new ActiveXObject("Microsoft.XMLHTTP");
    }

    return xmlhttp;
}

function minAjax(config) {

    /*Config Structure
            url:"reqesting URL"
            type:"GET or POST"
            method: "(OPTIONAL) True for async and False for Non-async | By default its Async"
            debugLog: "(OPTIONAL)To display Debug Logs | By default it is false"
            data: "(OPTIONAL) another Nested Object which should contains reqested Properties in form of Object Properties"
            success: "(OPTIONAL) Callback function to process after response | function(data,status)"
    */

    if (!config.url) {

        if (config.debugLog == true)
            console.log("No Url!");
        return;

    }

    if (!config.rtype) {

        if (config.debugLog == true)
            console.log("No Default type (GET/POST) given!");
        return;

    }

    if (!config.rmethod) {
        config.rmethod = true;
    }


    if (!config.debugLog) {
        config.debugLog = false;
    }

    var xmlhttp = initXMLhttp();

    xmlhttp.onreadystatechange = function() {

        if (xmlhttp.readyState == 4 && xmlhttp.status == 200) {

            if (config.success) {
                if (config.debugLog == true) {
                  console.log("SuccessResponse");
                  console.log("Response Data:" + xmlhttp.responseText);
                  }
//                config.success(xmlhttp.responseText, xmlhttp.readyState);
                var func_success = eval(config.success);
                func_success(xmlhttp.responseText);
            }

//            if (config.debugLog == true)
//                console.log("SuccessResponse");
//            if (config.debugLog == true)
//                console.log("Response Data:" + xmlhttp.responseText);

        } else {
            if (config.debugLog == true)
                if(xmlhttp.readyState == 4 && xmlhttp.status == 404) {
                    console.log("FailureResponse --> State: " + xmlhttp.readyState + "Status: " + xmlhttp.status);
                }
                else {
                    switch (xmlhttp.readyState) {
                        case 0 :
                        console.log("AJAX object contructed");
                        break;
                        case 1 :
                        console.log("AJAX request opened");
                        break;
                        case 2 :
                        console.log("AJAX response headers received");
                        break;
                        case 3 :
                        console.log("AJAX data is loading");
                        break;
                        default :
                        console.log("FailureResponse --> State: " + xmlhttp.readyState + "Status: " + xmlhttp.status);
                    }
                }
        }
    }

    var sendString = [],
        sendData = config.data;
    if( typeof sendData === "string" ){
        var tmpArr = String.prototype.split.call(sendData,'&');
        for(var i = 0, j = tmpArr.length; i < j; i++){
            var datum = tmpArr[i].split('=');
            sendString.push(encodeURIComponent(datum[0]) + "=" + encodeURIComponent(datum[1]));
        }
    }else if( typeof sendData === 'object' && !( sendData instanceof String || (FormData && sendData instanceof FormData) ) ){
        for (var k in sendData) {
            var datum = sendData[k];
            if( Object.prototype.toString.call(datum) == "[object Array]" ){
                for(var i = 0, j = datum.length; i < j; i++) {
                        sendString.push(encodeURIComponent(k) + "[]=" + encodeURIComponent(datum[i]));
                }
            }else{
                sendString.push(encodeURIComponent(k) + "=" + encodeURIComponent(datum));
            }
        }
    }
    sendString = sendString.join('&');

    if (config.rtype == "GET") {
        xmlhttp.open("GET", config.url + "?" + sendString, config.rmethod);
        xmlhttp.send();

        if (config.debugLog == true)
            console.log("GET fired at:" + config.url + "?" + sendString);
    }
    if (config.rtype == "POST") {
        xmlhttp.open("POST", config.url, config.rmethod);
        xmlhttp.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
        xmlhttp.send(sendString);

        if (config.debugLog == true)
            console.log("POST fired at:" + config.url + " || Data:" + sendString);
    }




}

function getValue(id) {
		domObject = document.getElementById(id);
		return domObject.value;
}

function nimSetInterval(strfunc,interval,arg) {
		var func_interval = eval(strfunc)
		var id = window.setInterval(func_interval,interval,arg)
		return id
}

function nimSetTimeout(strfunc,timeout,arg) {
		var func_timeout = eval(strfunc)
		var id = window.setTimeout(func_timeout,timeout,arg)
		return id
}

// ***** https://github.com/JamieLivingstone/styled-notifications *****

function nimShowNotificationSuccess(info) {
    window.createNotification({
    theme: 'success',
    showDuration: 3000
})({
    message: info
});
}

function nimShowNotificationError(info) {
window.createNotification({
    theme: 'error',
    showDuration: 3000
})({
    message: info
});
}

function nimShowNotificationWarning(info) {
window.createNotification({
    theme: 'warning',
    showDuration: 3000
})({
    message: info
});
}
