import { NavLink, Outlet } from "react-router-dom";
import { useSync } from "@/features/sync/useSync";

const links = [
  {
    to: "/app",
    end: true,
    label: "Accueil",
    icon: (
      <svg viewBox="0 0 24 24" aria-hidden>
        <path d="M4 10.5 12 4l8 6.5V20a1 1 0 0 1-1 1h-5v-6H10v6H5a1 1 0 0 1-1-1v-9.5Z" />
      </svg>
    ),
  },
  {
    to: "/app/ventes",
    label: "Cahier",
    icon: (
      <svg viewBox="0 0 24 24" aria-hidden>
        <path d="M7 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Z" />
        <path d="M9 8h6M9 12h6M9 16h4" />
      </svg>
    ),
  },
  {
    to: "/app/dettes",
    label: "Créances",
    icon: (
      <svg viewBox="0 0 24 24" aria-hidden>
        <circle cx="12" cy="12" r="8" />
        <path d="M12 8v8M9.5 10.5c.6-1 1.5-1.5 2.5-1.5s2 .7 2 2-1 2-2.5 2.5-2.5.8-2.5 2 1.1 2 2.5 2 1.9-.5 2.5-1.5" />
      </svg>
    ),
  },
  {
    to: "/app/profil",
    label: "Profil",
    icon: (
      <svg viewBox="0 0 24 24" aria-hidden>
        <circle cx="12" cy="9" r="3.5" />
        <path d="M6.5 19c1.5-3 3.5-4.5 5.5-4.5s4 1.5 5.5 4.5" />
      </svg>
    ),
  },
] as const;

export function AppShell() {
  useSync();

  return (
    <div className="app-shell">
      <div className="app-main">
        <Outlet />
      </div>
      <nav className="bottom-nav" aria-label="Navigation principale">
        {links.map((l) => (
          <NavLink
            key={l.to}
            to={l.to}
            end={"end" in l ? l.end : false}
            className={({ isActive }) => (isActive ? "active" : undefined)}
          >
            {l.icon}
            <span>{l.label}</span>
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
