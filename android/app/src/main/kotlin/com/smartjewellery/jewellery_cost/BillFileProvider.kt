package com.smartjewellery.jewellery_cost

import androidx.core.content.FileProvider

/** Own subclass so its manifest entry never clashes with plugins' providers. */
class BillFileProvider : FileProvider()
