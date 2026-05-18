import React from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import "./styles/global.css";

const container = document.getElementById("root");
if (!container) throw new Error("missing #root element");

createRoot(container).render(
    <React.StrictMode>
        <App />
    </React.StrictMode>,
);
