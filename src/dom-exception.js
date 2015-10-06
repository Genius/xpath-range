function DOMException(message, name) {
  this.message = message;
  this.name = name;
  this.stack = (new Error()).stack;
}

DOMException.prototype = new Error();

DOMException.prototype.toString = function () {
  return this.name + ': ' + this.message;
};

module.exports = DOMException;
