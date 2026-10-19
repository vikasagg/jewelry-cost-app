package com.swarnos.settings.domain;

/** Keys of the business settings in each shop's app_config table (BRD §16). */
public final class SettingKeys {
    public static final String SHOP_NAME = "shop.name";
    public static final String SHOP_ADDRESS = "shop.address";
    public static final String SHOP_PHONE = "shop.phone";
    public static final String SHOP_GSTIN = "shop.gstin";
    public static final String RATE_LIVE_PROVIDER = "rate.live.provider";
    public static final String RATE_LIVE_URL = "rate.live.url";
    public static final String RATE_LIVE_GOLD_FIELD = "rate.live.goldField";
    public static final String RATE_LIVE_SILVER_FIELD = "rate.live.silverField";
    public static final String RATE_LIVE_PLATINUM_FIELD = "rate.live.platinumField";
    public static final String BILL_ROUND_OFF = "bill.roundOff";
    public static final String DISCOUNT_MAX_PCT_SALES = "discount.maxPctSales";
    public static final String EXCHANGE_DEDUCTION_PCT = "exchange.deductionPct";
    public static final String OLD_METAL_DEDUCTION_PCT = "oldmetal.deductionPct";
    public static final String CASH_LIMIT_SALE = "cash.limit.sale";
    public static final String CASH_LIMIT_PURCHASE = "cash.limit.purchase";
    public static final String KYC_PAN_THRESHOLD = "kyc.pan.threshold";
    public static final String TALLY_STRICT_CLOSE = "tally.strictClose";
    public static final String BACKUP_TARGET_DIR = "backup.targetDir";
    public static final String INVOICE_PREFIX = "invoice.prefix";
    public static final String PURCHASE_PREFIX = "purchase.prefix";
    public static final String REPAIR_PREFIX = "repair.prefix";
    public static final String TAG_PREFIX = "tag.prefix";

    private SettingKeys() {}
}
