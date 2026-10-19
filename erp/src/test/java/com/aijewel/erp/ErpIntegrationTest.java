package com.aijewel.erp;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.util.LinkedMultiValueMap;

/** End-to-end over HTTP against the demo shop, a second shop, and a restored shop. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ErpIntegrationTest {
    static final Path DATA;

    static {
        try {
            DATA = Files.createTempDirectory("erp-test");
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
    }

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        r.add("app.data-dir", DATA::toString);
        r.add("app.demo.enabled", () -> "true");
        // mvn test -Derp.test.storage=CLOUD runs the same suite with the demo shop on PostgreSQL.
        String mode = System.getProperty("erp.test.storage", "LOCAL");
        r.add("app.demo.storage-mode", () -> mode);
        if (mode.equals("CLOUD")) {
            try (var c = java.sql.DriverManager.getConnection("jdbc:postgresql://localhost:5432/postgres", "postgres", "postgres");
                 var st = c.createStatement()) {
                st.execute("DROP DATABASE IF EXISTS jewel_demo WITH (FORCE)");
            } catch (java.sql.SQLException e) {
                throw new IllegalStateException("PostgreSQL is needed for -Derp.test.storage=CLOUD", e);
            }
        }
    }

    @Autowired
    TestRestTemplate http;

    // ---------- helpers ----------

    String login(String shop, String user) {
        return login(shop, user, "demo123");
    }

    @SuppressWarnings("unchecked")
    String login(String shop, String user, String password) {
        Map<String, Object> r = http.postForObject("/api/auth/login", Map.of("shop", shop, "username", user, "password", password), Map.class);
        assertThat(r).containsKey("token");
        return (String) r.get("token");
    }

    <T> ResponseEntity<T> call(HttpMethod method, String path, String token, Object body, Class<T> type) {
        HttpHeaders h = new HttpHeaders();
        h.setBearerAuth(token);
        h.setContentType(MediaType.APPLICATION_JSON);
        return http.exchange(path, method, new HttpEntity<>(body, h), type);
    }

    @SuppressWarnings("unchecked")
    Map<String, Object> post(String path, String token, Object body) {
        ResponseEntity<Map> r = call(HttpMethod.POST, path, token, body, Map.class);
        assertThat(r.getStatusCode().is2xxSuccessful()).as(path + " -> " + r.getBody()).isTrue();
        return r.getBody();
    }

    @SuppressWarnings("unchecked")
    Map<String, Object> get(String path, String token) {
        ResponseEntity<Map> r = call(HttpMethod.GET, path, token, null, Map.class);
        assertThat(r.getStatusCode().is2xxSuccessful()).as(path + " -> " + r.getBody()).isTrue();
        return r.getBody();
    }

    @SuppressWarnings("unchecked")
    List<Map<String, Object>> list(String path, String token) {
        ResponseEntity<List> r = call(HttpMethod.GET, path, token, null, List.class);
        assertThat(r.getStatusCode().is2xxSuccessful()).as(path).isTrue();
        return r.getBody();
    }

    static BigDecimal dec(Object o) {
        return new BigDecimal(o.toString());
    }

    // ---------- tests ----------

    @Test
    @SuppressWarnings("unchecked")
    void morningRateDerivesEveryPurityFromThe24kRate() {
        String owner = login("demo", "owner");
        Map<String, Object> today = get("/api/rates/today", owner);
        List<Map<String, Object>> lines = (List<Map<String, Object>>) ((Map<String, Object>) today.get("approved")).get("lines");
        Map<String, String> expected = Map.of("24K", "7500.000", "22K", "6900.000", "20K", "6300.000", "18K", "5700.000",
                "14K", "4500.000", "9K", "3000.000");
        expected.forEach((purity, rate) -> assertThat(lines).anySatisfy(l -> {
            assertThat(l.get("metal")).isEqualTo("GOLD");
            assertThat(l.get("purity_code")).isEqualTo(purity);
            assertThat(dec(l.get("rate_per_gram"))).isEqualByComparingTo(rate);
        }));
    }

    @Test
    void billMarksTagSoldAndTheSameTagCannotBeSoldTwice() {
        String sales = login("demo", "sales");
        Map<String, Object> item = list("/api/items?family=GOLD&purity=22K", sales).get(0);
        Map<String, Object> body = Map.of("lines", List.of(Map.of("item_id", item.get("id"))));
        Map<String, Object> quote = post("/api/sales/quote", sales, body);
        Map<String, Object> bill = post("/api/sales", sales, Map.of("lines", body.get("lines"),
                "payments", List.of(Map.of("mode", "CASH", "amount", quote.get("net_payable")))));
        assertThat(dec(bill.get("balance_due"))).isEqualByComparingTo("0");
        assertThat(get("/api/items/" + item.get("id"), sales).get("status")).isEqualTo("SOLD");

        ResponseEntity<Map> again = call(HttpMethod.POST, "/api/sales", sales, Map.of("lines", body.get("lines"),
                "payments", List.of(Map.of("mode", "CASH", "amount", quote.get("net_payable")))), Map.class);
        assertThat(again.getStatusCode().value()).isEqualTo(409);
        assertThat(list("/api/items/ledger-check", sales)).isEmpty();
    }

    @Test
    void salespersonCannotSeePurchasesCostOrSeenUnseenClass() {
        String sales = login("demo", "sales");
        assertThat(call(HttpMethod.GET, "/api/purchases", sales, null, Map.class).getStatusCode().value()).isEqualTo(403);
        assertThat(call(HttpMethod.GET, "/api/reports/purchase_by_class", sales, null, Map.class).getStatusCode().value()).isEqualTo(403);
        List<Map<String, Object>> items = list("/api/items", sales);
        assertThat(items).isNotEmpty().allSatisfy(i -> assertThat(i).doesNotContainKeys("purchase_class", "cost_amount"));

        String owner = login("demo", "owner");
        assertThat(list("/api/items", owner)).anySatisfy(i -> assertThat(i).containsKey("purchase_class"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void purchaseClassFollowsGstInvoiceAndPaymentMode() {
        String owner = login("demo", "owner");
        Map<String, Object> vendor = list("/api/parties?type=VENDOR", owner).get(0);
        long cat = ((Number) ((List<Map<String, Object>>) get("/api/masters", owner).get("categories")).stream()
                .filter(c -> "GCH".equals(c.get("code"))).findFirst().orElseThrow().get("id")).longValue();
        Map<String, Object> line = Map.of("category_id", cat, "purity_code", "22K", "gross_wt", "5.000", "cost_amount", "36000");

        Map<String, Object> seen = post("/api/purchases", owner, Map.of("party_id", vendor.get("id"), "purchase_kind", "FINISHED",
                "gst_invoice_no", "TEST/1", "lines", List.of(line), "payment", Map.of("bank", "37080")));
        assertThat(seen.get("purchase_class")).isEqualTo("SEEN");
        assertThat(seen.get("payment_mode")).isEqualTo("BANK");
        assertThat(dec(seen.get("total_amount"))).isEqualByComparingTo("37080.000");

        Map<String, Object> unseen = post("/api/purchases", owner, Map.of("party_id", vendor.get("id"), "purchase_kind", "FINISHED",
                "lines", List.of(line), "payment", Map.of("cash", "36000")));
        assertThat(unseen.get("purchase_class")).isEqualTo("UNSEEN");
        assertThat(dec(unseen.get("gst_amount"))).isEqualByComparingTo("0");
    }

    @Test
    @SuppressWarnings("unchecked")
    void eachShopHasItsOwnDatabase() {
        Map<String, Object> platform = http.postForObject("/api/platform/login", Map.of("username", "platform", "password", "platform@123"), Map.class);
        String op = (String) platform.get("token");
        post("/api/platform/tenants", op, Map.of("code", "isol", "name", "Isolation Test", "storageMode", "LOCAL",
                "ownerUsername", "owner", "ownerPassword", "secret1"));
        assertThat(Files.exists(DATA.resolve("tenants/isol/isol.mv.db"))).isTrue();

        String isol = login("isol", "owner", "secret1");
        assertThat(list("/api/items?status=ALL", isol)).isEmpty();
        assertThat(list("/api/parties", isol)).isEmpty();
        // A new shop has no approved rate, so billing waits.
        ResponseEntity<Map> bill = call(HttpMethod.POST, "/api/sales/quote", isol, Map.of("lines", List.of(Map.of("tag_code", "T000001"))), Map.class);
        assertThat(bill.getStatusCode().value()).isEqualTo(409);
        // The demo shop still has its stock, and a shop token cannot reach the platform API.
        assertThat(list("/api/items", login("demo", "owner"))).isNotEmpty();
        assertThat(call(HttpMethod.GET, "/api/platform/tenants", isol, null, String.class).getStatusCode().value()).isEqualTo(403);
    }

    @Test
    @SuppressWarnings("unchecked")
    void encryptedUsbBackupVerifiesAndRestoresAsANewShop() throws Exception {
        String owner = login("demo", "owner");
        Path usb = DATA.resolve("usb-drive");
        Map<String, Object> b = post("/api/backup", owner, Map.of("password", "usb-secret", "target_dir", usb.toString()));
        assertThat(b.get("verified")).isEqualTo(true);
        Path file = Path.of((String) b.get("path"));
        assertThat(file).startsWith(usb).exists();
        assertThat(Files.readString(usb.resolve(b.get("file") + ".sha256"))).startsWith((String) b.get("sha256"));
        assertThat(new String(Files.readAllBytes(file), java.nio.charset.StandardCharsets.ISO_8859_1))
                .doesNotContain("Demo Jewellers").doesNotContain("tag_code");   // encrypted at rest

        String op = (String) http.postForObject("/api/platform/login", Map.of("username", "platform", "password", "platform@123"), Map.class).get("token");
        LinkedMultiValueMap<String, Object> form = new LinkedMultiValueMap<>();
        form.add("file", new ByteArrayResource(Files.readAllBytes(file)) {
            @Override
            public String getFilename() {
                return "demo.jbk";
            }
        });
        form.add("password", "wrong-pass");
        form.add("code", "restored");
        HttpHeaders h = new HttpHeaders();
        h.setBearerAuth(op);
        h.setContentType(MediaType.MULTIPART_FORM_DATA);
        ResponseEntity<Map> wrong = http.exchange("/api/platform/restore", HttpMethod.POST, new HttpEntity<>(form, h), Map.class);
        assertThat(wrong.getStatusCode().value()).isEqualTo(400);

        form.set("password", "usb-secret");
        ResponseEntity<Map> ok = http.exchange("/api/platform/restore", HttpMethod.POST, new HttpEntity<>(form, h), Map.class);
        assertThat(ok.getStatusCode().is2xxSuccessful()).as(String.valueOf(ok.getBody())).isTrue();
        assertThat(((Number) ok.getBody().get("rows")).longValue()).isEqualTo(((Number) b.get("rows")).longValue());

        String restored = login("restored", "owner");
        assertThat(list("/api/items?status=ALL", restored)).hasSameSizeAs(list("/api/items?status=ALL", owner));
        // New records in the restored shop continue numbering after the restored ones.
        Map<String, Object> p = post("/api/parties", restored, Map.of("party_type", "CUSTOMER", "name", "After restore"));
        assertThat(((Number) p.get("id")).longValue()).isGreaterThan(5);
    }

    @Test
    @SuppressWarnings("unchecked")
    void tallyFindsMissingAndUnknownTagsAndNeedsDecisionsBeforeClosing() {
        String stock = login("demo", "stock");
        String manager = login("demo", "manager");
        Map<String, Object> s = post("/api/tally", stock, Map.of());
        long id = ((Number) s.get("id")).longValue();
        List<Map<String, Object>> items = list("/api/items", stock);
        List<String> codes = items.stream().skip(1).map(i -> (String) i.get("tag_code")).toList();
        Map<String, Object> after = post("/api/tally/" + id + "/scan", stock, Map.of("codes", codes, "text", "NOPE123\n" + codes.get(0)));
        assertThat((List<?>) after.get("missing")).hasSize(1);
        assertThat((List<?>) after.get("unknown")).hasSize(1);

        assertThat(call(HttpMethod.POST, "/api/tally/" + id + "/close", stock, null, Map.class).getStatusCode().value()).isEqualTo(403);
        assertThat(call(HttpMethod.POST, "/api/tally/" + id + "/close", manager, null, Map.class).getStatusCode().value()).isEqualTo(409);

        Map<String, Object> cmp = post("/api/tally/" + id + "/compare", manager, null);
        for (Map<String, Object> v : (List<Map<String, Object>>) cmp.get("variances")) {
            post("/api/tally/variance/" + v.get("id"), manager, Map.of(
                    "resolution", "MISSING".equals(v.get("kind")) ? "MARK_LOST" : "ACCEPTED", "reason", "test"));
        }
        assertThat(post("/api/tally/" + id + "/close", manager, null).get("status")).isEqualTo("CLOSED");
        assertThat(get("/api/items/" + items.get(0).get("id"), stock).get("status")).isEqualTo("LOST");
    }

    @Test
    @SuppressWarnings("unchecked")
    void voiceSearchReturnsFiltersAndMatchingStock() {
        String sales = login("demo", "sales");
        Map<String, Object> r = post("/api/search/ask", sales, Map.of("text", "diamond jewellery below 50000"));
        assertThat((List<String>) r.get("chips")).contains("Price ≤ ₹50,000");
        List<Map<String, Object>> results = (List<Map<String, Object>>) r.get("results");
        assertThat(results).isNotEmpty().allSatisfy(i -> {
            assertThat(i.get("family")).isEqualTo("DIAMOND");
            assertThat(dec(i.get("price"))).isLessThanOrEqualTo(new BigDecimal("50000"));
        });
    }

    @Test
    @SuppressWarnings("unchecked")
    void everyReportDashboardAndBookRuns() {
        String owner = login("demo", "owner");
        Map<String, Object> catalogue = get("/api/reports", owner);
        for (String name : catalogue.keySet()) {
            Map<String, Object> r = get("/api/reports/" + name + "?from=2026-01-01&to=2030-12-31", owner);
            assertThat(r).containsKeys("title", "columns", "rows");
            ResponseEntity<String> csv = call(HttpMethod.GET, "/api/reports/" + name + "/csv", owner, null, String.class);
            assertThat(csv.getStatusCode().is2xxSuccessful()).as(name).isTrue();
        }
        Map<String, Object> d = get("/api/dashboard", owner);
        assertThat(d).containsKeys("stock", "sales_today", "books", "alerts");
        for (String book : List.of("cash", "bank", "gold", "silver", "platinum")) {
            assertThat(get("/api/ledgers/" + book, owner)).containsKey("closing");
        }
        Map<String, Object> customer = list("/api/parties?type=CUSTOMER", owner).get(0);
        assertThat(get("/api/parties/" + customer.get("id"), owner)).containsKeys("items_bought", "ledger", "balance");
    }

    @Test
    @SuppressWarnings("unchecked")
    void repairMovesThroughKarigarAndShowsMetalDifference() {
        String sales = login("demo", "sales");
        Map<String, Object> customer = list("/api/parties?type=CUSTOMER", sales).get(0);
        Map<String, Object> karigar = list("/api/parties?type=KARIGAR", sales).get(0);
        Map<String, Object> job = post("/api/repairs", sales, Map.of("customer_id", customer.get("id"), "description", "Chain clasp",
                "metal", "GOLD", "purity_code", "22K", "weight_in", "10.000", "estimate", "500", "advance", "100"));
        long id = ((Number) job.get("id")).longValue();
        post("/api/repairs/" + id + "/status", sales, Map.of("status", "WITH_KARIGAR", "karigar_id", karigar.get("id"), "weight", "10.000"));
        Map<String, Object> ready = post("/api/repairs/" + id + "/status", sales, Map.of("status", "READY", "weight", "9.950"));
        assertThat(dec(ready.get("karigar_difference"))).isEqualByComparingTo("-0.050");
        assertThat(call(HttpMethod.POST, "/api/repairs/" + id + "/status", sales, Map.of("status", "RECEIVED"), Map.class)
                .getStatusCode().value()).isEqualTo(409);
        Map<String, Object> done = post("/api/repairs/" + id + "/status", sales, Map.of("status", "DELIVERED", "charges", "500", "amount", "400"));
        assertThat(done.get("status")).isEqualTo("DELIVERED");
        assertThat(dec(done.get("metal_difference"))).isEqualByComparingTo("-0.050");
        assertThat(get("/api/repairs/lookup?no=" + job.get("job_no"), sales).get("id")).isEqualTo(job.get("id"));
    }
}
