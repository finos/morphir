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
    
    var app = angular.module("TradesExample", []);
    
    app.controller("pageCtrl", function ($scope, $http) {
        
        $scope.pageGlobal = {
            data: {
                Product: [],
                Trade: []
            },
            calculatedFields: calculatedFields
        };
        
        $scope.newProduct = {};
        $scope.addProduct = function (product) {
            $scope.pageGlobal.data.Product.push(product);
            relink($scope.pageGlobal.data);
            $scope.newProduct = {};
        };
        
        $scope.newTrade = {};
        $scope.addTrade = function (trade) {
            $scope.pageGlobal.data.Trade.push(trade);
            relink($scope.pageGlobal.data);
            $scope.newTrade = {};
        };
        
        $scope.getCusips = function (products) {
            var cusips = [];
            products.forEach(function (product) {
                if (cusips.indexOf(product.Product_cusip) < 0) {
                    cusips.push(product.Product_cusip);
                }
            });
            return cusips;
        };
        
        var productQuery = {
            nodeType: 'SelectExpr',
            children: [
              {
                  nodeType: 'FromExpr',
                  name: 'urn:Product'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:Product/cusip'
              },
              {
                  nodeType: 'ParameterExpr',
                  name: 'urn:Product/closePriceUsd'
              }
            ]
        };
        
        $http.post("/rates/query/executeQuery.json?nocache=" + (new Date()).getTime(), productQuery).
            success(function (data, status, headers, config) {
                data.forEach(function (product) {
                    $scope.pageGlobal.data.Product.push(product);
                });
                relink($scope.pageGlobal.data);
                console.log($scope.pageGlobal.data);
            }).
            error(function (data, status, headers, config) {
                console.log(data);
            });
        
        var tradeQuery = {
                nodeType: 'SelectExpr',
                children: [
                  {
                      nodeType: 'FromExpr',
                      name: 'urn:Trade'
                  },
                  {
                      nodeType: 'ParameterExpr',
                      name: 'urn:Trade/tradeId'
                  },
                  {
                      nodeType: 'ParameterExpr',
                      name: 'urn:Product/cusip'
                  },
                  {
                      nodeType: 'ParameterExpr',
                      name: 'urn:Trade/quantity'
                  },
                  {
                      nodeType: 'ParameterExpr',
                      name: 'urn:Trade/side'
                  },
                  {
                      nodeType: 'ParameterExpr',
                      name: 'urn:Product/closePriceUsd'
                  }
                ]
            };
            
        $http.post("/rates/query/executeQuery.json?nocache=" + (new Date()).getTime(), tradeQuery).
            success(function (data, status, headers, config) {
                data.forEach(function (trade) {
                    $scope.pageGlobal.data.Trade.push(trade);
                });
                relink($scope.pageGlobal.data);
                console.log($scope.pageGlobal.data);
            }).
            error(function (data, status, headers, config) {
                console.log(data);
            });
            
    });
    
}(angular));