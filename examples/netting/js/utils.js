Number.prototype.formatMoney = function (n, x) {
    var re = '\\d(?=(\\d{' + (x || 3) + '})+' + (n > 0 ? '\\.' : '$') + ')';
    return this.toFixed(Math.max(0, ~~n)).replace(new RegExp(re, 'g'), '$&,');
};
var isNumber = function (n) {
    return !isNaN(parseFloat(n)) && isFinite(n);
};
function LocalDate (stringValue) {
    this.date = new Date (stringValue);
    this.diffDays = function (otherDate) {
        var oneDay = 24*60*60*1000;
        var firstDate = this.date;
        var secondDate = otherDate.date;
        var diffDays = Math.round(Math.abs((firstDate.getTime() - secondDate.getTime())/(oneDay)));
        return diffDays;
    }
}