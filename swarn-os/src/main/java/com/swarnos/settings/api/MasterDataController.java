package com.swarnos.settings.api;

import com.swarnos.settings.api.dto.CategoryRequest;
import com.swarnos.settings.api.dto.IdResponse;
import com.swarnos.settings.api.dto.MastersResponse;
import com.swarnos.settings.api.dto.PriceFactorRequest;
import com.swarnos.settings.domain.Purity;
import com.swarnos.settings.service.MasterDataService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class MasterDataController {
    private final MasterDataService masters;

    public MasterDataController(MasterDataService masters) {
        this.masters = masters;
    }

    @GetMapping("/masters")
    public MastersResponse masters() {
        return new MastersResponse(masters.activeCategories(), masters.activePurities(), masters.locations());
    }

    @PutMapping("/purities/{id}")
    public Purity changePriceFactor(@PathVariable long id, @Valid @RequestBody PriceFactorRequest req) {
        return masters.changePriceFactor(id, req.priceFactor());
    }

    @PostMapping("/categories")
    public IdResponse saveCategory(@RequestBody CategoryRequest req) {
        if (req.id() == null) {
            return new IdResponse(masters.createCategory(new MasterDataService.NewCategory(req.code(), req.name(), req.family(),
                    req.tracking(), req.makingType(), req.makingValue(), req.wastagePct(), req.gstPct())));
        }
        masters.updateCategory(req.id(), new MasterDataService.CategoryChanges(req.name(), req.makingType(), req.makingValue(),
                req.wastagePct(), req.gstPct(), req.active()));
        return new IdResponse(req.id());
    }
}
