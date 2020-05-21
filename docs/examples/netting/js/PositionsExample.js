(function (angular) {
    
    var relink = function (data) {
        data.Product.forEach(function (product) {
            product.Trade = [];
            data.Trade.forEach(function (trade) {
                if (trade.Product_cusip == product.Product_cusip) {
                    product.Trade.push(trade);
                };
            });
        });
        data.Trade.forEach(function (trade) {
            trade.Product = [];
            data.Product.forEach(function (product) {
                if (trade.Product_cusip == product.Product_cusip) {
                    trade.Product_closePriceUsd = product.Product_closePriceUsd;
                    trade.Product.push(product);
                };
            });
        });
    };
    
    var copyAttributes = function (source, target) {
        for (var attr in source) {
            if (source.hasOwnProperty(attr)) target[attr] = source[attr];
        }
    };
    
    var app = angular.module("PositionsExample", []);
    
    app.controller("pageCtrl", function ($scope, $http) {
        
        console.log(new LocalDate("2015-08-13").diffDays(new LocalDate("2015-08-16")));
        
        $scope.pageGlobal = {
            data: {
                LongPosition: [],
                ShortPosition: []
            },
            calculatedFields: calculatedFields,
            selectedLong: null,
            selectedShort: null,
            showExcluded: false,
            explainSrc: ''
        };
        
        $scope.selectLong = function (longPos) {
            $scope.pageGlobal.explainSrc =
                "./rates/fields/rules.html?field=urn:Matching/matches";
            $scope.pageGlobal.selectedShort = null;
            $scope.pageGlobal.selectedLong = longPos;
            $scope.pageGlobal.data.ShortPosition.forEach(function (shortPos) {
                shortPos.notionalValue = shortPos.ShortPosition_notionalValue; 
            });
            $scope.pageGlobal.data.LongPosition.forEach(function (longPos) {
                longPos.notionalValue = longPos.LongPosition_notionalValue; 
            });
            $scope.pageGlobal.data.ShortPosition.forEach(function (shortPos) {
                var matchRow = {};
                copyAttributes($scope.pageGlobal.selectedLong, matchRow);
                copyAttributes(shortPos, matchRow);
                var matched = $scope.pageGlobal.calculatedFields.Matching_matches(matchRow);
                if (matched) {
                    shortPos.matched = true;
                } else {
                    shortPos.matched = false;
                }
            });
            var apply = true;
            $scope.pageGlobal.data.LongPosition.forEach(function (longPos) {
                if (apply) {
                    $scope.pageGlobal.data.ShortPosition.forEach(function (shortPos) {
                        var matchRow = {};
                        copyAttributes(longPos, matchRow);
                        copyAttributes(shortPos, matchRow);
                        var matched = $scope.pageGlobal.calculatedFields.Matching_matches(matchRow);
                        if (matched) {
                            shortPos.matched = true;
                            var moveValue = Math.min(longPos.notionalValue, shortPos.notionalValue);
                            shortPos.notionalValue -= moveValue;
                            longPos.notionalValue -= moveValue;
                        } else {
                            shortPos.matched = false;
                        }
                    });
                }
                if ($scope.pageGlobal.selectedLong == longPos) {
                    apply = false;
                }
            });
        };
        
        $scope.selectShort = function (shortPos) {
            $scope.pageGlobal.selectedShort = shortPos;
            $scope.pageGlobal.explainSrc =
                "rates/fields/insight_matches_" +
                $scope.pageGlobal.selectedLong.LongPosition_id + "_" + shortPos.ShortPosition_id + ".html";
        };
        
        $scope.longPositionClass = function (longPos) {
            var classes = "";
            if ($scope.pageGlobal.selectedLong == longPos) {
                classes += "selected";
            }
            if (longPos.notionalValue == 0) {
                classes += " zeroed"
            }
            return classes;
        };
        
        $scope.shortPositionClass = function (shortPos) {
            var classes = "";
            if (shortPos.matched) {
                classes += "matched";
            }
            if ($scope.pageGlobal.selectedShort == shortPos) {
                classes += " selected"
            }
            if (shortPos.notionalValue == 0) {
                classes += " zeroed"
            }
            return classes;
        };
        
        var longPositionQuery = {
            nodeType: 'SelectExpr',
            children: [
              {
                  nodeType: 'FromExpr',
                  name: 'urn:LongPosition'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:LongPosition/id'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:Product/cusip'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:LongPosition/productCategory'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:LongPosition/tenor'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:LongPosition/maturityDate'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:LongPosition/notionalValue'
              }
            ]
        };
        
        $http.get("rates/query/long_positions.json").
            success(function (data, status, headers, config) {
                data.forEach(function (longPosition) {
                    longPosition.notionalValue = longPosition.LongPosition_notionalValue;
                    $scope.pageGlobal.data.LongPosition.push(longPosition);
                });
                //relink($scope.pageGlobal.data);
                console.log($scope.pageGlobal.data);
            }).
            error(function (data, status, headers, config) {
                console.log(data);
            });
        
        var shortPositionQuery = {
            nodeType: 'SelectExpr',
            children: [
              {
                  nodeType: 'FromExpr',
                  name: 'urn:ShortPosition'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:ShortPosition/id'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:Product/cusip'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:ShortPosition/productCategory'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:ShortPosition/tenor'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:ShortPosition/maturityDate'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:ShortPosition/notionalValue'
              }
            ]
        };
        
        $http.get("rates/query/short_positions.json").
            success(function (data, status, headers, config) {
                data.forEach(function (shortPosition) {
                    shortPosition.notionalValue = shortPosition.ShortPosition_notionalValue;
                    $scope.pageGlobal.data.ShortPosition.push(shortPosition);
                });
                //relink($scope.pageGlobal.data);
                console.log($scope.pageGlobal.data);
            }).
            error(function (data, status, headers, config) {
                console.log(data);
            });
        
    });
    
}(angular));