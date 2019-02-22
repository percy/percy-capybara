(function(f){if(typeof exports==="object"&&typeof module!=="undefined"){module.exports=f()}else if(typeof define==="function"&&define.amd){define([],f)}else{var g;if(typeof window!=="undefined"){g=window}else if(typeof global!=="undefined"){g=global}else if(typeof self!=="undefined"){g=self}else{g=this}g.PercyAgent = f()}})(function(){var define,module,exports;return (function(){function r(e,n,t){function o(i,f){if(!n[i]){if(!e[i]){var c="function"==typeof require&&require;if(!f&&c)return c(i,!0);if(u)return u(i,!0);var a=new Error("Cannot find module '"+i+"'");throw a.code="MODULE_NOT_FOUND",a}var p=n[i]={exports:{}};e[i][0].call(p.exports,function(r){var n=e[i][1][r];return o(n||r)},p,p.exports,r,e,n,t)}return n[i].exports}for(var u="function"==typeof require&&require,i=0;i<t.length;i++)o(t[i]);return o}return r})()({1:[function(require,module,exports){
"use strict";
// This is setup like this so you can include percy-agent.js onto your webpage
// and then simply use `var percyAgent = new PercyAgent()` to create a new client instance.
// tslint:disable-next-line:no-var-requires
module.exports = require('./percy-agent').default;

},{"./percy-agent":3}],2:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const constants_1 = require("../services/constants");
class PercyAgentClient {
    constructor(agentHost, xhr) {
        this.agentConnected = false;
        this.agentHost = agentHost;
        this.xhr = new xhr() || new XMLHttpRequest();
        this.healthCheck();
    }
    post(path, data) {
        if (!this.agentConnected) {
            console.warn('percy agent not started.');
            return;
        }
        this.xhr.open('post', `${this.agentHost}${path}`, false); // synchronous request
        this.xhr.setRequestHeader('Content-Type', 'application/json');
        this.xhr.send(JSON.stringify(data));
    }
    healthCheck() {
        try {
            this.xhr.open('get', `${this.agentHost}${constants_1.default.HEALTHCHECK_PATH}`, false);
            this.xhr.onload = () => {
                if (this.xhr.status === 200) {
                    this.agentConnected = true;
                }
            };
            this.xhr.send();
        }
        catch (_a) {
            this.agentConnected = false;
        }
    }
}
exports.PercyAgentClient = PercyAgentClient;

},{"../services/constants":5}],3:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const constants_1 = require("../services/constants");
const percy_agent_client_1 = require("./percy-agent-client");
const serialize_cssom_1 = require("./serialize-cssom");
class PercyAgent {
    constructor(options = {}) {
        this.client = null;
        this.defaultDoctype = '<!DOCTYPE html>';
        this.clientInfo = options.clientInfo || null;
        this.environmentInfo = options.environmentInfo || null;
        // Default to 'true' unless explicitly disabled.
        this.handleAgentCommunication = options.handleAgentCommunication !== false;
        this.domTransformation = options.domTransformation || null;
        this.port = options.port || constants_1.default.PORT;
        if (this.handleAgentCommunication) {
            this.xhr = options.xhr || XMLHttpRequest;
            this.client = new percy_agent_client_1.PercyAgentClient(`http://localhost:${this.port}`, this.xhr);
        }
    }
    snapshot(name, options = {}) {
        const documentObject = options.document || document;
        const domSnapshot = this.domSnapshot(documentObject);
        if (this.handleAgentCommunication && this.client) {
            this.client.post(constants_1.default.SNAPSHOT_PATH, {
                name,
                url: documentObject.URL,
                // enableJavascript is deprecated. Use enableJavaScript
                enableJavaScript: options.enableJavaScript || options.enableJavascript,
                widths: options.widths,
                // minimumHeight is deprecated. Use minHeight
                minHeight: options.minHeight || options.minimumHeight,
                clientInfo: this.clientInfo,
                environmentInfo: this.environmentInfo,
                domSnapshot,
            });
        }
        return domSnapshot;
    }
    domSnapshot(documentObject) {
        const doctype = this.getDoctype(documentObject);
        const dom = this.stabilizeDOM(documentObject);
        let domClone = dom.cloneNode(true);
        // Sometimes you'll want to transform the DOM provided into one ready for snapshotting
        // For example, if your test suite runs tests in an element inside a page that
        // lists all yours tests. You'll want to "hoist" the contents of the testing container to be
        // the full page. Using a dom transformation is how you'd acheive that.
        if (this.domTransformation) {
            domClone = this.domTransformation(domClone);
        }
        return doctype + domClone.outerHTML;
    }
    getDoctype(documentObject) {
        return documentObject.doctype ? this.doctypeToString(documentObject.doctype) : this.defaultDoctype;
    }
    doctypeToString(doctype) {
        const publicDeclaration = doctype.publicId ? ` PUBLIC "${doctype.publicId}" ` : '';
        const systemDeclaration = doctype.systemId ? ` SYSTEM "${doctype.systemId}" ` : '';
        return `<!DOCTYPE ${doctype.name}` + publicDeclaration + systemDeclaration + '>';
    }
    serializeInputElements(doc) {
        const domClone = doc.documentElement;
        const inputNodes = domClone.getElementsByTagName('input');
        const inputElements = Array.prototype.slice.call(inputNodes);
        inputElements.forEach((elem) => {
            switch (elem.type) {
                case 'checkbox':
                case 'radio':
                    if (elem.checked) {
                        elem.setAttribute('checked', '');
                    }
                    break;
                default:
                    elem.setAttribute('value', elem.value);
            }
        });
        return doc;
    }
    stabilizeDOM(doc) {
        let stabilizedDOM = doc;
        stabilizedDOM = serialize_cssom_1.serializeCssOm(stabilizedDOM);
        stabilizedDOM = this.serializeInputElements(stabilizedDOM);
        // more calls to come here
        return stabilizedDOM.documentElement;
    }
}
exports.default = PercyAgent;

},{"../services/constants":5,"./percy-agent-client":2,"./serialize-cssom":4}],4:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// Take all the CSS created in the CSS Object Model (CSSOM), and inject it
// into the DOM so Percy can render it safely in our browsers.
// Design doc:
// https://docs.google.com/document/d/1Rmm8osD-HwSHRpb8pQ_1wLU09XeaCV5AqMtQihk_BmM/edit
function serializeCssOm(document) {
    [].slice.call(document.styleSheets).forEach((styleSheet) => {
        // Make sure it has a rulesheet, does NOT have a href (no external stylesheets),
        // and isn't already in the DOM.
        const hasHref = styleSheet.href;
        const ownerNode = styleSheet.ownerNode;
        const hasStyleInDom = ownerNode.innerText && ownerNode.innerText.length > 0;
        if (!hasHref && !hasStyleInDom && styleSheet.cssRules) {
            const serializedStyles = [].slice
                .call(styleSheet.cssRules)
                .reduce((prev, cssRule) => {
                return prev + cssRule.cssText;
            }, '');
            // Append the serialized styles to the styleSheet's ownerNode to minimize
            // the chances of messing up the cascade order.
            const serializedSheet = document.createElement('style');
            serializedSheet.setAttribute('data-percy-cssom-serialized', 'true');
            serializedSheet.type = 'text/css';
            serializedSheet.appendChild(document.createTextNode(serializedStyles));
            ownerNode.appendChild(serializedSheet);
        }
    });
    return document;
}
exports.serializeCssOm = serializeCssOm;

},{}],5:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
class Constants {
}
Constants.PORT = 5338;
// Agent Service paths
Constants.SNAPSHOT_PATH = '/percy/snapshot';
Constants.STOP_PATH = '/percy/stop';
Constants.HEALTHCHECK_PATH = '/percy/healthcheck';
exports.default = Constants;

},{}]},{},[1])(1)
});
