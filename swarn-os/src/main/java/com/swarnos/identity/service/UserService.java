package com.swarnos.identity.service;

import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.identity.domain.User;
import com.swarnos.identity.repository.UserRepository;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.security.Role;
import java.util.List;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Staff accounts of a shop. */
@Service
public class UserService {
    private final UserRepository users;
    private final PasswordEncoder encoder;
    private final AuditService audit;

    public UserService(UserRepository users, PasswordEncoder encoder, AuditService audit) {
        this.users = users;
        this.encoder = encoder;
        this.audit = audit;
    }

    public record NewUser(String username, String fullName, Role role, String password) {}

    public record UserChanges(String fullName, Role role, Boolean active, String password) {}

    public List<User> list() {
        CurrentUser.require(Permission.USERS);
        return users.findAll();
    }

    @Transactional
    public User create(NewUser req) {
        CurrentUser.require(Permission.USERS);
        return insert(req);
    }

    /** First owner of a new shop, created during provisioning (no signed-in user). */
    public User createOwner(String username, String fullName, String password) {
        return insert(new NewUser(username == null || username.isBlank() ? "owner" : username, fullName == null
                || fullName.isBlank() ? "Owner" : fullName, Role.OWNER, password));
    }

    @Transactional
    public User update(long id, UserChanges changes) {
        CurrentUser.require(Permission.USERS);
        User u = users.findById(id).orElseThrow(() -> BusinessException.notFound("User not found"));
        Role role = changes.role() == null ? u.role() : shopRole(changes.role());
        users.updateProfile(id, changes.fullName() == null ? u.fullName() : changes.fullName(), role,
                changes.active() == null ? u.active() : changes.active());
        if (changes.password() != null && !changes.password().isBlank()) {
            checkPassword(changes.password());
            users.updatePassword(id, encoder.encode(changes.password()));
        }
        audit.record("USER_UPDATE", "user", id, "role " + role);
        return users.findById(id).orElseThrow();
    }

    private User insert(NewUser req) {
        if (req.username() == null || req.username().isBlank()) throw BusinessException.validation("Username is required.");
        checkPassword(req.password());
        String username = req.username().trim().toLowerCase();
        Role role = shopRole(req.role());
        long id = users.insert(username, req.fullName() == null || req.fullName().isBlank() ? username : req.fullName().trim(),
                encoder.encode(req.password()), role);
        audit.record("USER_CREATE", "user", id, username + " as " + role);
        return users.findById(id).orElseThrow();
    }

    private static Role shopRole(Role role) {
        if (role == null || !role.isShopRole()) {
            throw BusinessException.validation("Role must be OWNER, MANAGER, SALES, ACCOUNTANT or STOCK.");
        }
        return role;
    }

    private static void checkPassword(String password) {
        if (password == null || password.length() < User.MIN_PASSWORD_LENGTH) {
            throw BusinessException.validation("Password needs at least " + User.MIN_PASSWORD_LENGTH + " characters.");
        }
    }
}
