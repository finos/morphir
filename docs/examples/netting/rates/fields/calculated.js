var calculatedFields = {
    Matching_matches: function (data) {
        return (calculatedFields.Matching_sameCategory(data) && calculatedFields.Matching_maturityWithinDelta(data));
    },
    Matching_maturityWithinDelta: function (data) {
        return (["Swaps","FRA"].indexOf(data.LongPosition_productCategory) > -1) ? (
            ((data.LongPosition_tenor <= 30)) ? (
                ((new LocalDate(data.LongPosition_maturityDate).diffDays(new LocalDate(data.ShortPosition_maturityDate))) <= 0)
            ) : (
                ((data.LongPosition_tenor <= 365)) ? (
                    ((new LocalDate(data.LongPosition_maturityDate).diffDays(new LocalDate(data.ShortPosition_maturityDate))) <= 7)
                ) : (
                    ((new LocalDate(data.LongPosition_maturityDate).diffDays(new LocalDate(data.ShortPosition_maturityDate))) <= 30)
                )
            )
        ) : (
            ((data.LongPosition_productCategory == "Forwards")) ? (
                ((data.LongPosition_tenor <= 30)) ? (
                    ((new LocalDate(data.LongPosition_maturityDate).diffDays(new LocalDate(data.ShortPosition_maturityDate))) <= 0)
                ) : (
                    ((data.LongPosition_tenor <= 365)) ? (
                        ((new LocalDate(data.LongPosition_maturityDate).diffDays(new LocalDate(data.ShortPosition_maturityDate))) <= 7)
                    ) : (
                        ((new LocalDate(data.LongPosition_maturityDate).diffDays(new LocalDate(data.ShortPosition_maturityDate))) <= 30)
                    )
                )
            ) : (
                ((data.LongPosition_productCategory == "Future")) ? (
                    ((new LocalDate(data.LongPosition_maturityDate).diffDays(new LocalDate(data.ShortPosition_maturityDate))) <= 7)
                ) : (
                    false
                )
            )
        );
    },
    Matching_sameCategory: function (data) {
        return (data.LongPosition_productCategory == data.ShortPosition_productCategory);
    },
    Product_borrowValue: function (data) {
        return data.Trade
            .filter(function (data) {
                return (data.Trade_side == "Borrow");
            })
            .reduce(function (prev, curr) {
                return prev + calculatedFields.Trade_value(curr);
            }, 0);
    },
    Product_volumeIndicator: function (data) {
        return ((calculatedFields.Product_borrowValue(data) > 1000000)) ? (
            "High"
        ) : (
            ((calculatedFields.Product_borrowValue(data) > 1000)) ? (
                "Medium"
            ) : (
                "Low"
            )
        );
    },
    Trade_value: function (data) {
        return (data.Product_closePriceUsd * data.Trade_quantity);
    }
};