package com.swarnos.identity.api;

import com.swarnos.identity.api.dto.UserRequest;
import com.swarnos.identity.domain.User;
import com.swarnos.identity.service.UserService;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/users")
public class UserController {
    private final UserService users;

    public UserController(UserService users) {
        this.users = users;
    }

    @GetMapping
    public List<User> list() {
        return users.list();
    }

    @PostMapping
    public User create(@RequestBody UserRequest req) {
        return users.create(new UserService.NewUser(req.username(), req.fullName(), req.role(), req.password()));
    }

    @PutMapping("/{id}")
    public User update(@PathVariable long id, @RequestBody UserRequest req) {
        return users.update(id, new UserService.UserChanges(req.fullName(), req.role(), req.active(), req.password()));
    }
}
