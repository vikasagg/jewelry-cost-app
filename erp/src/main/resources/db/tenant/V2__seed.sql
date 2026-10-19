-- Seed masters for a new shop. All of it is editable later from Settings.

INSERT INTO location (code, name, kind) VALUES
 ('C1', 'Counter 1', 'COUNTER'),
 ('C2', 'Counter 2', 'COUNTER'),
 ('VAULT', 'Vault / Safe', 'VAULT'),
 ('REPAIR', 'Repair custody', 'REPAIR'),
 ('KARIGAR', 'With karigar / vendor', 'EXTERNAL');

-- Purity factors decided by the owner (D-01): share of the 24K rate used for price.
-- fineness is the true metal content, used for fine weight in the metal ledger.
INSERT INTO purity (metal, code, price_factor, fineness, sort_order) VALUES
 ('GOLD', '24K', 1.000000, 0.999000, 1),
 ('GOLD', '22K', 0.920000, 0.916000, 2),
 ('GOLD', '20K', 0.840000, 0.833000, 3),
 ('GOLD', '18K', 0.760000, 0.750000, 4),
 ('GOLD', '14K', 0.600000, 0.585000, 5),
 ('GOLD', '9K',  0.400000, 0.375000, 6),
 ('SILVER', '999', 1.000000, 0.999000, 1),
 ('SILVER', '925', 0.925000, 0.925000, 2),
 ('SILVER', '800', 0.800000, 0.800000, 3),
 ('PLATINUM', '950', 0.950000, 0.950000, 1),
 ('PLATINUM', '900', 0.900000, 0.900000, 2);

INSERT INTO category (code, name, family, metal, pricing_mode, tracking, tag_type, making_type, making_value, wastage_pct, gst_pct) VALUES
 ('GCH', 'Gold Chain',            'GOLD', 'GOLD', 'METAL', 'PIECE', 'QR', 'PERCENT', 12, 0, 3),
 ('LGR', 'Ladies Gold Ring',      'GOLD', 'GOLD', 'METAL', 'PIECE', 'QR', 'PERCENT', 14, 0, 3),
 ('GGR', 'Gents Gold Ring',       'GOLD', 'GOLD', 'METAL', 'PIECE', 'QR', 'PERCENT', 12, 0, 3),
 ('GE',  'Gold Earring',          'GOLD', 'GOLD', 'METAL', 'PIECE', 'QR', 'PERCENT', 14, 0, 3),
 ('GBG', 'Gold Bangle',           'GOLD', 'GOLD', 'METAL', 'PIECE', 'QR', 'PERCENT', 10, 0, 3),
 ('GNS', 'Gold Necklace Set',     'GOLD', 'GOLD', 'METAL', 'PIECE', 'QR', 'PERCENT', 15, 2, 3),
 ('GPD', 'Gold Pendant',          'GOLD', 'GOLD', 'METAL', 'PIECE', 'QR', 'PERCENT', 14, 0, 3),
 ('GPS', 'Pendant Set',           'GOLD', 'GOLD', 'METAL', 'PIECE', 'QR', 'PERCENT', 14, 0, 3),
 ('GMS', 'Mangalsutra',           'GOLD', 'GOLD', 'METAL', 'PIECE', 'QR', 'PERCENT', 12, 0, 3),
 ('DE',  'Diamond Earring',       'DIAMOND', 'GOLD', 'METAL', 'PIECE', 'QR', 'PER_GRAM', 1500, 0, 3),
 ('DRG', 'Diamond Ring',          'DIAMOND', 'GOLD', 'METAL', 'PIECE', 'QR', 'PER_GRAM', 1500, 0, 3),
 ('DPD', 'Diamond Pendant',       'DIAMOND', 'GOLD', 'METAL', 'PIECE', 'QR', 'PER_GRAM', 1500, 0, 3),
 ('DNS', 'Diamond Necklace Set',  'DIAMOND', 'GOLD', 'METAL', 'PIECE', 'QR', 'PER_GRAM', 1800, 0, 3),
 ('DBG', 'Diamond Bangle',        'DIAMOND', 'GOLD', 'METAL', 'PIECE', 'QR', 'PER_GRAM', 1500, 0, 3),
 ('PTR', 'Platinum Ring',         'PLATINUM', 'PLATINUM', 'METAL', 'PIECE', 'QR', 'PERCENT', 15, 0, 3),
 ('PTC', 'Platinum Chain',        'PLATINUM', 'PLATINUM', 'METAL', 'PIECE', 'QR', 'PERCENT', 15, 0, 3),
 ('SCN', 'Silver Coin',           'SILVER', 'SILVER', 'METAL', 'PIECE', 'QR', 'PER_GRAM', 5, 0, 3),
 ('SUT', 'Silver Utensil',        'SILVER', 'SILVER', 'METAL', 'PIECE', 'QR', 'PER_GRAM', 15, 0, 3),
 ('SAN', 'Silver Anklet (Payal)', 'SILVER_ORNAMENT', 'SILVER', 'METAL', 'PIECE', 'QR', 'PER_GRAM', 25, 0, 3),
 ('STR', 'Silver Toe Ring',       'SILVER_ORNAMENT', 'SILVER', 'METAL', 'PIECE', 'QR', 'PER_GRAM', 25, 0, 3),
 ('SBR', 'Silver Bracelet',       'SILVER_ORNAMENT', 'SILVER', 'METAL', 'PIECE', 'QR', 'PER_GRAM', 25, 0, 3),
 ('GFT', 'Gift Article',          'GIFTING', NULL, 'FIXED', 'QUANTITY', 'QR', 'FIXED', 0, 0, 18),
 ('WTC', 'Watch',                 'GIFTING', NULL, 'FIXED', 'PIECE', 'QR', 'FIXED', 0, 0, 18);

-- Business configuration (BRD §16). Values reflect the owner decisions of 19 Oct 2026.
INSERT INTO app_config (config_key, config_value, description) VALUES
 ('shop.name',                 'My Jewellery Shop', 'Shop name printed on bills'),
 ('shop.address',              '',                  'Address printed on bills'),
 ('shop.phone',                '',                  'Phone printed on bills'),
 ('shop.gstin',                '',                  'Shop GSTIN printed on bills'),
 ('rate.live.provider',        'DEMO',              'Live rate source: NONE, DEMO or HTTP. A live rate is only a proposal until approved'),
 ('rate.live.url',             '',                  'HTTP provider: URL returning JSON'),
 ('rate.live.goldField',       'gold24k',           'HTTP provider: JSON field with 24K gold per gram'),
 ('rate.live.silverField',     'silver',            'HTTP provider: JSON field with fine silver per gram'),
 ('rate.live.platinumField',   'platinum',          'HTTP provider: JSON field with platinum per gram'),
 ('rate.entryUnit.gold',       '10',                'Grams per rate entered for gold (10 = rate per 10 g)'),
 ('rate.entryUnit.silver',     '1000',              'Grams per rate entered for silver (1000 = rate per kg)'),
 ('rate.entryUnit.platinum',   '10',                'Grams per rate entered for platinum'),
 ('bill.roundOff',             'NONE',              'NONE or RUPEE (round bill to nearest rupee)'),
 ('discount.maxPctSales',      '5',                 'Largest discount % a salesperson may give without manager'),
 ('exchange.deductionPct',     '2',                 'Default deduction % on old gold/silver taken in exchange'),
 ('oldmetal.deductionPct',     '3',                 'Default deduction % on old metal bought for cash/bank'),
 ('cash.limit.sale',           '',                  'Cash receipt limit per bill (blank = no limit, D-05)'),
 ('cash.limit.purchase',       '',                  'Cash payment limit per purchase (blank = no limit, D-05)'),
 ('kyc.pan.threshold',         '',                  'Bill value needing PAN (blank = no limit, D-05)'),
 ('offline.maxHours',          '24',                'Hours a shop may work offline (D-06)'),
 ('tally.strictClose',         'true',              'Block tally close while any variance is unresolved'),
 ('backup.targetDir',          '',                  'Folder for backups, e.g. the USB drive (E:\JewelBackup or /media/usb). Blank = data/backups'),
 ('invoice.prefix',            'INV',               'Sales invoice number prefix'),
 ('purchase.prefix',           'PUR',               'Purchase number prefix'),
 ('repair.prefix',             'REP',               'Repair job number prefix'),
 ('tag.prefix',                'T',                 'Prefix for generated tag codes'),
 ('ai.voice.enabled',          'true',              'Voice search on/off'),
 ('ai.voice.language',         'en-IN',             'Speech language: en-IN or hi-IN');
